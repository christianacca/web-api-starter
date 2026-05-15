#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:scriptPath = Join-Path $PSScriptRoot 'poll-and-approve.ps1'

    # Create a temp directory that will shadow the real 'gh' on PATH with a controllable fake.
    $script:fakeGhDir = New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) "fake-gh-$(New-Guid)")

    # Fake gh logic: reads GH_FAKE_* env vars to control exit code and output per call type.
    $fakeGhImpl = @'
$url    = $args[1]
$isPost = $args -contains '--method'
if ($url -match '/jobs$') {
    $env:GH_FAKE_JOBS_OUTPUT
    exit [int]($env:GH_FAKE_JOBS_EXIT_CODE ?? 0)
} elseif ($isPost) {
    exit [int]($env:GH_FAKE_POST_EXIT_CODE ?? 0)
} else {
    $env:GH_FAKE_PENDING_OUTPUT
    exit [int]($env:GH_FAKE_PENDING_EXIT_CODE ?? 0)
}
'@
    Set-Content -Path (Join-Path $script:fakeGhDir 'gh-impl.ps1') -Value $fakeGhImpl -Encoding utf8

    if ($IsWindows) {
        Set-Content -Path (Join-Path $script:fakeGhDir 'gh.cmd') `
            -Value '@pwsh -NoProfile -NonInteractive -File "%~dp0gh-impl.ps1" %*' -Encoding ascii
    } else {
        $ghPath = Join-Path $script:fakeGhDir 'gh'
        Set-Content -Path $ghPath -Value "#!/bin/bash`nexec pwsh -NoProfile -NonInteractive -File `"$(dirname `$0)/gh-impl.ps1`" `"`$@`"" -Encoding utf8
        & chmod +x $ghPath
    }

    $script:originalPath = $env:PATH
    $env:PATH = "$($script:fakeGhDir)$([IO.Path]::PathSeparator)$env:PATH"
}

AfterAll {
    $env:PATH = $script:originalPath
    Remove-Item $script:fakeGhDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "poll-and-approve.ps1 catch scenarios" {

    BeforeAll {
        # Runs the script in a child pwsh process (avoids 'exit' killing Pester) and returns
        # combined stdout+stderr as a single string for assertion.
        function Invoke-Script {
            & pwsh -NoProfile -NonInteractive -File $script:scriptPath `
                -Repo 'org/repo' -RunId '123' -EnvironmentAllowList '["dev"]' `
                -MaxWait 2 -PollInterval 1 2>&1 | Out-String
        }
    }

    BeforeEach {
        $env:GH_FAKE_JOBS_EXIT_CODE    = '0'
        $env:GH_FAKE_JOBS_OUTPUT       = '{"jobs":[{"name":"other-job","status":"completed"}]}'
        $env:GH_FAKE_PENDING_EXIT_CODE = '0'
        $env:GH_FAKE_PENDING_OUTPUT    = '[]'
        $env:GH_FAKE_POST_EXIT_CODE    = '0'
    }

    AfterEach {
        'GH_FAKE_JOBS_EXIT_CODE', 'GH_FAKE_JOBS_OUTPUT',
        'GH_FAKE_PENDING_EXIT_CODE', 'GH_FAKE_PENDING_OUTPUT',
        'GH_FAKE_POST_EXIT_CODE' | ForEach-Object { Remove-Item "env:$_" -ErrorAction SilentlyContinue }
    }

    Context "gh api jobs call fails with non-zero exit code" {
        It "logs a warning with the exit code and response body" {
            $env:GH_FAKE_JOBS_EXIT_CODE = '1'
            $env:GH_FAKE_JOBS_OUTPUT    = 'HTTP 401: Bad credentials'

            Invoke-Script | Should -Match 'gh api jobs call failed \(exit 1\)'
        }
    }

    Context "gh api jobs returns a successful response with malformed JSON" {
        It "logs a warning from the catch block with the parse error" {
            $env:GH_FAKE_JOBS_OUTPUT = 'not { valid json'

            Invoke-Script | Should -Match 'Failed to check jobs'
        }
    }

    Context "gh api jobs response is valid JSON but missing the .jobs property" {
        It "throws on property access and logs a warning from the catch block" {
            $env:GH_FAKE_JOBS_OUTPUT = '{"something_else":[]}'

            Invoke-Script | Should -Match 'Failed to check jobs'
        }
    }

    Context "gh api jobs response has jobs where each job object is missing .name" {
        It "throws on .name access in Where-Object and logs a warning from the catch block" {
            $env:GH_FAKE_JOBS_OUTPUT = '{"jobs":[{"status":"completed"}]}'

            Invoke-Script | Should -Match 'Failed to check jobs'
        }
    }

    Context "gh api jobs response has jobs where each job object is missing .status" {
        It "throws on .status access in Where-Object and logs a warning from the catch block" {
            $env:GH_FAKE_JOBS_OUTPUT = '{"jobs":[{"name":"other-job"}]}'

            Invoke-Script | Should -Match 'Failed to check jobs'
        }
    }

    Context "gh api pending_deployments call fails with non-zero exit code" {
        It "logs a warning with the exit code and response body" {
            $env:GH_FAKE_PENDING_EXIT_CODE = '1'
            $env:GH_FAKE_PENDING_OUTPUT    = 'HTTP 401: Bad credentials'

            Invoke-Script | Should -Match 'gh api pending_deployments call failed \(exit 1\)'
        }
    }

    Context "gh api pending_deployments returns a successful response with malformed JSON" {
        It "logs a warning from the catch block with the parse error" {
            $env:GH_FAKE_PENDING_OUTPUT = 'not { valid json'

            Invoke-Script | Should -Match 'Failed to check pending deployments'
        }
    }
}
