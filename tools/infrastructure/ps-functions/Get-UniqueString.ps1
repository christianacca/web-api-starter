function Get-UniqueString {
    param([string] $Value)
    begin {
        $md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
    }
    process {
        $utf8 = [system.Text.Encoding]::UTF8
        $bytes = $md5.ComputeHash($utf8.GetBytes($Value))
        [Guid]::new($bytes).ToString().Replace('-', '')[0..12] -Join ''
    }
    end {
        $md5.Dispose()
    }
}