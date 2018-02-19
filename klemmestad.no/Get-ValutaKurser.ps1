# Velg formater
$Valutakode = '' # Blank for ALLE. Eks. 'USD' for kun amerikanske dollar mot NOK
$lastNObservations = 1 # Hvor mange kurser bakover i tid vil du ha data for
$Skilletegn = 'semicolon' # 'comma', 'semicolon', 'tab' eller 'space'
$Tidsakse = 'flat' # 'flat', 'x' eller 'y'
$FulleNavn = 'false' # 'false' eller 'true'. Eks: 'false' = NOK, 'true' = Norske kroner

# Sett sammen valgene til riktig URL
$Uri = 'https://data.norges-bank.no/api/data/EXR/B.{0}.NOK.SP?lastNObservations={1}&format=csv-:-{2}-{3}-{4}' -F $Valutakode, $lastNObservations, $Skilletegn, $FulleNavn, $Tidsakse

# Kolonnenavn
$Valutakurser = "APIversjon;Frekvens;Valuta;NOK;Kurstype;Dato;Kurs;Desimaler;Ukjent;Enhet;Tidspunkt`n"

# Hent CSV data og legg dem til etter kolonnenavnene + gjør om på desimalpunktum
$Valutakurser += (Invoke-RestMethod -Uri $Uri -Method GET) -replace '(;\d+)\.(\d+;)', '$1,$2'

$Filnavn = '{0}\Downloads\valutakurser.csv' -F $Env:USERPROFILE

$Valutakurser | Set-Content -Path $Filnavn -Encoding UTF8
