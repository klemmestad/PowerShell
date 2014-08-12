## SETUP ENVIRONMENT
# Find "Advanced Monitoring Agent" service and use path to locate files
$gfimaxagent = Get-WmiObject Win32_Service | Where-Object { $_.Name -eq 'Advanced Monitoring Agent' }
$gfimaxexe = $gfimaxagent.PathName
$gfimaxpath = Split-Path $gfimaxagent.PathName.Replace([char]34,"") -Parent
$XmlFile = $gfimaxpath + [char]92 + "247_Config_new.xml"

[xml]$XmlContent = Get-Content $XmlFile
$XmlPath = "checks"
$Property = "uid"
$XmlValues = @{}
Foreach ($XmlElement in $XmlContent.$XmlPath.ChildNodes)
{
	$ElementValues = ""
	Foreach($XmlValue in $XmlElement.ChildNodes | Sort-Object name)
	{
		$ElementValues = $ElementValues + $XmlValue.Name + $XmlValue.InnerText
	}
	$XmlValues[$XmlElement.$Property] = $ElementValues
}

$XmlDuplicates = @{}
Foreach ($XmlValue in $XmlValues.Values)
{
	$Items = @($XmlValues.Keys | Where { $XmlValues[$_] -eq $XmlValue})
	If ($Items.Count -gt 1)
	{
		If (!($XmlDuplicates[$Items[0]])) { $XmlDuplicates[$Items[0]] = $Items }
	}
	
}

Foreach ($XmlDuplicate in $XmlDuplicates.Keys)
{
	
	For ($i = 1; $i -lt $XmlDuplicates[$XmlDuplicate].Count; $i++)
	{
		$XPath = "//" + $XmlPath + "/*[@" + $Property +"=" + $XmlDuplicates[$XmlDuplicate][$i]+"]"
		$ChildToBeRemoved = $XmlContent.SelectSingleNode($XPath)
		$ChildToBeRemoved.ParentNode.RemoveChild($ChildToBeRemoved)
	}
}

$XmlContent.Save($XmlFile)
