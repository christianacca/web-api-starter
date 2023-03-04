function Get-StorageRbacAccess {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Blob', 'Table', 'File', 'Queue')]
        [string[]] $Usage,

        [Parameter(Mandatory)]
        [ValidateSet('Readonly', 'ReadWrite')]
        [string[]] $AccessLevel
    )
    if ($AccessLevel -eq 'Readonly') {
        @(
            if ($Usage -eq 'Blob') { 'Storage Blob Data Reader' }
            if ($Usage -eq 'Table') { 'Storage Table Data Reader' }
            if ($Usage -eq 'File') { 'Storage File Data SMB Share Reader' }
            if ($Usage -eq 'Queue') { 'Storage Queue Data Reader' }
        )
    }
    if ($AccessLevel -eq 'ReadWrite') {
        @(
            if ($Usage -eq 'Blob') { 'Storage Blob Data Contributor' }
            if ($Usage -eq 'Table') { 'Storage Table Data Contributor' }
            if ($Usage -eq 'File') { 'Storage File Data SMB Share Contributor' }
            if ($Usage -eq 'Queue') { 'Storage Queue Data Contributor' }
        )
    }
}