# A small QueryXML function I got from Jon Czerwinski in an autotask forum
# https://community.autotask.com/forums/p/15090/38343.aspx#38343
# I have modified it to handle more fields and expressions
 
function New-ATWSQuery {
    [CmdletBinding()]
    param(
        [Parameter(Position=0,Mandatory=$true)]
        [string]$Entity,
        [Parameter(Position=1,Mandatory=$true)]
        [string]$Field,
        [Parameter(Position=2,Mandatory=$false)]
        [string]$Expression,
        [Parameter(Position=3,Mandatory=$false)]
        [string]$Value,
        [Parameter(Position=4,Mandatory=$false)]
        [string]$Field2,
        [Parameter(Position=5,Mandatory=$false)]
        [string]$Expression2,
        [Parameter(Position=6,Mandatory=$false)]
        [string]$Value2,
        [Parameter(Position=7,Mandatory=$false)]
        [string]$Field3,
        [Parameter(Position=8,Mandatory=$false)]
        [string]$Expression3,
        [Parameter(Position=9,Mandatory=$false)]
        [string]$Value3,
        [Parameter(Position=10,Mandatory=$false)]
        [string]$Field4,
        [Parameter(Position=11,Mandatory=$false)]
        [string]$Expression4,
        [Parameter(Position=12,Mandatory=$false)]
        [string]$Value4,
        [Parameter(Position=13,Mandatory=$false)]
        [string]$Field5,
        [Parameter(Position=14,Mandatory=$false)]
        [string]$Expression5,
        [Parameter(Position=15,Mandatory=$false)]
        [string]$Value5
 
 )
    $query = "<queryxml><entity>$Entity</entity><query><condition><field>$Field<expression op=""$Expression"">$Value</expression></field></condition>"
 
    If (!($Field2 -eq ""))  {
        $query= "$query <condition><field>$Field2<expression op=""$Expression2"">$Value2</expression></field></condition>"
    }
 
    If (!($Field3 -eq ""))  {
         $query= "$query <condition><field>$Field3<expression op=""$Expression3"">$Value3</expression></field></condition>"
    } 
 
    If (!($Field4 -eq ""))  {
         $query= "$query <condition><field>$Field4<expression op=""$Expression4"">$Value4</expression></field></condition>"
    }
 
    If (!($Field5 -eq ""))  {
         $query= "$query <condition><field>$Field5<expression op=""$Expression5"">$Value5</expression></field></condition>"
    } 
 
    $query = "$query </query></queryxml>"
 
$query
 
}