$f = 'apis/journey_map/213_journey_cell_dedupe_apply_POST.xs'
$c = Get-Content $f -Raw

# 1. Add defaults to bool inputs
$c = $c -replace '    bool dry_run\?(?!=)', '    bool dry_run?=true'
$c = $c -replace '    bool confirm\?(?!=)', '    bool confirm?=false'

# 2. Remove the entire $is_dry var block (with leading comment)
$c = $c -replace '(?s)\s*// .. Resolve flags \(default dry_run=true, confirm=false\) ..\s*var \$is_dry \{\s*value = \$input\.dry_run == null \|\| \$input\.dry_run == true\s*\}\s*', "`n  "

# 3. Fix precondition
$c = $c -replace 'precondition \(\$is_dry \|\| \$input\.confirm\)', 'precondition ($input.dry_run == true || $input.confirm == true)'

# 4. Fix remaining $is_dry references
$c = $c -replace 'if \(\$is_dry == false\)', 'if ($input.dry_run == false)'
$c = $c -replace 'if \(\$is_dry\) \{', 'if ($input.dry_run == true) {'

Set-Content -Path $f -Value $c -NoNewline -Encoding UTF8
Write-Host 'fix applied'
