#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    Set-StrictMode -Version Latest

    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
    . "$repoRoot/.github/actions/tests/TestHarness.ps1"

    $script:scriptPath = Join-Path $repoRoot '.github/actions/auto-approve-deployments/poll-and-approve.ps1'

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
                -Repo 'org/repo' -RunId '123' -EnvironmentAllowList @('dev') `
                -SelfJobName 'auto_approve' `
                -MaxWaitSeconds 2 -PollIntervalSeconds 1 2>&1 | Out-String
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
        It "logs an error from the catch block" {
            $env:GH_FAKE_JOBS_EXIT_CODE = '1'
            $env:GH_FAKE_JOBS_OUTPUT    = 'HTTP 401: Bad credentials'

            Invoke-Script | Should -Match 'Failed to check jobs: .+'
        }
    }

    Context "gh api jobs returns a successful response with malformed JSON" {
        It "logs a warning from the catch block with the parse error" {
            $env:GH_FAKE_JOBS_OUTPUT = 'not { valid json'

            Invoke-Script | Should -Match 'Failed to check jobs: .+'
        }
    }

    Context "gh api jobs response is valid JSON but missing the .jobs property" {
        It "throws on property access and logs a warning from the catch block" {
            $env:GH_FAKE_JOBS_OUTPUT = '{"something_else":[]}'

            Invoke-Script | Should -Match 'Failed to check jobs: .+'
        }
    }

    Context "gh api jobs response has jobs where each job object is missing .name" {
        It "throws on .name access in Where-Object and logs a warning from the catch block" {
            $env:GH_FAKE_JOBS_OUTPUT = '{"jobs":[{"status":"completed"}]}'

            Invoke-Script | Should -Match 'Failed to check jobs: .+'
        }
    }

    Context "gh api jobs response has jobs where each job object is missing .status" {
        It "throws on .status access in Where-Object and logs a warning from the catch block" {
            $env:GH_FAKE_JOBS_OUTPUT = '{"jobs":[{"name":"other-job"}]}'

            Invoke-Script | Should -Match 'Failed to check jobs: .+'
        }
    }

    Context "gh api pending_deployments call fails with non-zero exit code" {
        It "logs an error from the catch block" {
            $env:GH_FAKE_PENDING_EXIT_CODE = '1'
            $env:GH_FAKE_PENDING_OUTPUT    = 'HTTP 401: Bad credentials'

            Invoke-Script | Should -Match 'Failed to check pending deployments: .+'
        }
    }

    Context "gh api pending_deployments returns a successful response with malformed JSON" {
        It "logs a warning from the catch block with the parse error" {
            $env:GH_FAKE_PENDING_OUTPUT = 'not { valid json'

            Invoke-Script | Should -Match 'Failed to check pending deployments: .+'
        }
    }
}

Describe "poll-and-approve.ps1 happy-path and logic scenarios" {

    BeforeAll {
        # Parameterised variant of Invoke-Script so individual tests can override -EnvironmentAllowList.
        function Invoke-Script {
            param(
                [string[]] $EnvironmentAllowList = @('dev')
            )
            & pwsh -NoProfile -NonInteractive -File $script:scriptPath `
                -Repo 'org/repo' -RunId '123' -EnvironmentAllowList $EnvironmentAllowList `
                -SelfJobName 'auto_approve' `
                -MaxWaitSeconds 2 -PollIntervalSeconds 1 2>&1 | Out-String
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

    Context "all other jobs completed and no pending deployments" {
        It "exits early and logs the success message" {
            # BeforeEach default: other-job=completed, pending=[]
            Invoke-Script | Should -Match 'All other jobs completed and no pending deployments\. Exiting\.'
        }
    }

    Context "jobs never reach completed state within MaxWait" {
        It "logs the timeout message and does not exit early" {
            $env:GH_FAKE_JOBS_OUTPUT = '{"jobs":[{"name":"other-job","status":"in_progress"}]}'

            $output = Invoke-Script
            $output | Should -Match 'Polling timed out after 2s\.'
            $output | Should -Not -Match 'Exiting\.'
        }
    }

    Context "a pending deployment whose environment name is in the allow list" {
        It "logs the approval message with the matching environment id" {
            $env:GH_FAKE_PENDING_OUTPUT = '[{"environment":{"id":42,"name":"dev"}}]'

            Invoke-Script | Should -Match 'Approving pending deployments \(ids: 42\)'
        }
    }

    Context "a pending deployment whose environment name is NOT in the allow list" {
        It "does not attempt to approve the non-allowed environment" {
            $env:GH_FAKE_PENDING_OUTPUT = '[{"environment":{"id":99,"name":"prod"}}]'

            Invoke-Script | Should -Not -Match 'Approving pending deployments'
        }
    }

    Context "the auto_approve job is in_progress alongside other completed jobs" {
        It "excludes auto_approve from the done-check and exits early once all other jobs are completed" {
            $env:GH_FAKE_JOBS_OUTPUT = '{"jobs":[{"name":"deploy","status":"completed"},{"name":"auto_approve","status":"in_progress"}]}'

            Invoke-Script | Should -Match 'All other jobs completed and no pending deployments\. Exiting\.'
        }
    }
}
