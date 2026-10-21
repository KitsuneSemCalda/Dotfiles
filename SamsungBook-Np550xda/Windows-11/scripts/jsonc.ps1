# Windows Terminal uses JSON with comments and trailing commas.
# Preserve characters inside strings while removing those extensions.
function ConvertFrom-Jsonc {
    param([string]$Text)

    $withoutComments = [System.Text.StringBuilder]::new()
    $inString = $false
    $escaped = $false
    $inLineComment = $false
    $inBlockComment = $false
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $char = $Text[$i]
        $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
        if ($inLineComment) {
            if ($char -eq "`n" -or $char -eq "`r") {
                $inLineComment = $false
                $null = $withoutComments.Append($char)
            }
            continue
        }
        if ($inBlockComment) {
            if ($char -eq '*' -and $next -eq '/') {
                $inBlockComment = $false
                $i++
            } elseif ($char -eq "`n" -or $char -eq "`r") {
                $null = $withoutComments.Append($char)
            }
            continue
        }
        if ($inString) {
            $null = $withoutComments.Append($char)
            if ($escaped) { $escaped = $false }
            elseif ($char -eq '\') { $escaped = $true }
            elseif ($char -eq '"') { $inString = $false }
            continue
        }
        if ($char -eq '"') { $inString = $true }
        elseif ($char -eq '/' -and $next -eq '/') {
            $inLineComment = $true
            $i++
            continue
        } elseif ($char -eq '/' -and $next -eq '*') {
            $inBlockComment = $true
            $i++
            continue
        }
        $null = $withoutComments.Append($char)
    }
    if ($inString -or $inBlockComment) { throw 'Windows Terminal settings.json has an unfinished string or comment' }

    $json = $withoutComments.ToString()
    $withoutTrailingCommas = [System.Text.StringBuilder]::new()
    $inString = $false
    $escaped = $false
    for ($i = 0; $i -lt $json.Length; $i++) {
        $char = $json[$i]
        if ($inString) {
            if ($escaped) { $escaped = $false }
            elseif ($char -eq '\') { $escaped = $true }
            elseif ($char -eq '"') { $inString = $false }
        } elseif ($char -eq '"') {
            $inString = $true
        } elseif ($char -eq ',') {
            $j = $i + 1
            while ($j -lt $json.Length -and [char]::IsWhiteSpace($json[$j])) { $j++ }
            if ($j -lt $json.Length -and ($json[$j] -eq '}' -or $json[$j] -eq ']')) { continue }
        }
        $null = $withoutTrailingCommas.Append($char)
    }
    return ConvertFrom-Json -InputObject ($withoutTrailingCommas.ToString())
}
