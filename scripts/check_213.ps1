$f = 'apis/journey_map/213_journey_cell_dedupe_apply_POST.xs'
$bytes = [System.IO.File]::ReadAllBytes($f)
$first3 = ($bytes[0..2] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
Write-Host "First 3 bytes (hex): $first3"
Write-Host "Total size: $($bytes.Length)"

# Find any em-dash sequences (UTF-8 E2 80 94) or replacement chars
$emCount = 0
for ($i = 0; $i -lt $bytes.Length - 2; $i++) {
    if ($bytes[$i] -eq 0xE2 -and $bytes[$i+1] -eq 0x80 -and $bytes[$i+2] -eq 0x94) { $emCount++ }
}
Write-Host "Em-dash (UTF-8) occurrences: $emCount"

# Find lines with non-ASCII bytes
$text = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
$lines = $text -split "`n"
for ($i = 0; $i -lt $lines.Length; $i++) {
    $line = $lines[$i]
    foreach ($c in $line.ToCharArray()) {
        if ([int][char]$c -gt 127) {
            Write-Host ("Line {0}: non-ASCII char U+{1:X4} `'{2}`'  ::  {3}" -f ($i+1), [int][char]$c, $c, $line.Trim())
            break
        }
    }
}
