function ConvertTo-HumanSize {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [ulong]$Bytes,
    [ValidateRange(0, 99)]
    [int]$DecimalDigits = 2
  )

  begin {
    $units = @('B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB', 'EiB', 'ZiB', 'YiB')
  }

  process {
    $order = $Bytes -eq 0 ? 0 : [Math]::Floor([Math]::Log($Bytes, 1024))
    $order = [Math]::Min($order, $units.Length - 1)

    "{0:N$DecimalDigits} {1}" -f ($Bytes / [Math]::Pow(1024, $order)), $units[$order]
  }
}
