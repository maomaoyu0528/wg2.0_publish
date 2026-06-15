if ($args.Length -lt 2) {
    Write-Error "Please provide the cluster name and region"
    return
}

$clustername=$args[0]
$region=$args[1]
if ($args.Length -ge 3) {
    $profile=$args[2]
} else {
    $profile="default"
}

Get-ChildItem -Path . -Recurse -File -Filter *.tpl | ForEach-Object {
    $file=$_
    $new_file=$file.FullName.Replace(".tpl","")

    $content=(Get-Content $file.FullName) -replace "{{clustername}}",$clustername -replace "{{region}}",$region -replace "{{profile}}",$profile

    Set-Content $new_file -Value $content
}