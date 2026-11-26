<#
.SYNOPSIS
  nimbus-demo-lite turnkey deployer for native Windows PowerShell (5.1+ or 7+).
  Needs only Terraform and the AWS CLI. No WSL, Ansible, CDK, Helm or Vault.

.EXAMPLE
  .\deploy.ps1 -Offline preflight render-vars validate
  .\deploy.ps1 preflight
  .\deploy.ps1 deploy
  .\deploy.ps1 outputs
  .\deploy.ps1 destroy

.NOTES
  Commands : preflight, render-vars, validate, plan, deploy (alias all), outputs, destroy, help
  Flags    : -Offline (no AWS calls), -Yes (no prompts), -EnvFile <path>
             (--offline / --yes / --env-file <path> also accepted)
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Offline,
    [switch]$Yes,
    [string]$EnvFile = "",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Commands
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ------------------------------------------------------------------ args
$cmdList = New-Object System.Collections.Generic.List[string]
$argsIn = @()
if ($Commands) { $argsIn = @($Commands) }
for ($i = 0; $i -lt $argsIn.Count; $i++) {
    $a = $argsIn[$i]
    switch -Regex ($a) {
        '^--?offline$'  { $script:Offline = $true; continue }
        '^--?yes$|^-y$' { $script:Yes = $true; continue }
        '^--?env-file$' { $i++; $script:EnvFile = $argsIn[$i]; continue }
        default         { $cmdList.Add($a.ToLowerInvariant()) }
    }
}
if ($cmdList.Count -eq 0) { $cmdList.Add("help") }

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  [ok] $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "  [warn] $msg" -ForegroundColor Yellow }
function Fail($msg)       { Write-Host "  [fail] $msg" -ForegroundColor Red; exit 1 }

# ------------------------------------------------------------------ paths
function ConvertTo-WinPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $p }
    $p = $p.Trim()
    if ($p -match '^~([\\/]|$)') { $p = $HOME + $p.Substring(1) }
    if ($p -match '^/mnt/([a-zA-Z])(/.*)?$') { $p = $Matches[1].ToUpper() + ':' + $Matches[2] }
    elseif ($p -match '^/([a-zA-Z])(/.*)?$') { $p = $Matches[1].ToUpper() + ':' + $Matches[2] }
    $p = $p -replace '/', '\'
    if ($p -match '^[A-Za-z]:$') { $p += '\' }
    if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $script:RepoRootResolved $p }
    try { $p = [System.IO.Path]::GetFullPath($p) } catch { }
    if ($p.Length -gt 3) { $p = $p.TrimEnd('\') }
    return $p
}
function ConvertTo-TfPath([string]$p) { return ($p -replace '\\', '/') }

# ------------------------------------------------------------------ env file
$script:Cfg = [ordered]@{}
$script:RepoRootResolved = $ScriptDir

function Expand-Value([string]$v) {
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        $k = $m.Groups[1].Value
        if ($script:Cfg.Contains($k)) { return [string]$script:Cfg[$k] }
        if ($k -eq 'HOME') { return $HOME }
        $ev = [Environment]::GetEnvironmentVariable($k)
        if ($ev) { return $ev }
        return ''
    }
    return [regex]::Replace($v, '\$\{([A-Za-z_][A-Za-z0-9_]*)\}', $evaluator)
}

function Read-EnvFile([string]$path) {
    $lines = [System.IO.File]::ReadAllLines($path)
    foreach ($raw in $lines) {
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        if ($line -notmatch '^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { continue }
        $key = $Matches[1]; $rest = $Matches[2].Trim()
        if ($rest.StartsWith("'")) {
            $end = $rest.IndexOf("'", 1); if ($end -lt 0) { $end = $rest.Length }
            $val = $rest.Substring(1, [Math]::Max(0, $end - 1))
        } elseif ($rest.StartsWith('"')) {
            $end = $rest.IndexOf('"', 1); if ($end -lt 0) { $end = $rest.Length }
            $val = $rest.Substring(1, [Math]::Max(0, $end - 1))
        } else {
            $val = ($rest -replace '\s+#.*$', '').Trim()
        }
        $val = Expand-Value $val
        if ($key -eq 'REPO_ROOT') {
            if ([string]::IsNullOrWhiteSpace($val)) { $val = $ScriptDir }
            $val = ConvertTo-WinPath $val
            if (-not (Test-Path -LiteralPath $val)) {
                Write-Warn2 "REPO_ROOT '$val' not found; using script folder '$ScriptDir'"
                $val = $ScriptDir
            }
            $script:RepoRootResolved = $val
        }
        $script:Cfg[$key] = $val
    }
}

if ($EnvFile -eq "") {
    $EnvFile = Join-Path $ScriptDir "deploy.env"
    if (-not (Test-Path -LiteralPath $EnvFile)) {
        $EnvFile = Join-Path $ScriptDir "deploy.env.example"
        Write-Warn2 "deploy.env not found - using deploy.env.example (copy it to deploy.env and edit the <-- CHANGE lines)"
    }
}
if (-not (Test-Path -LiteralPath $EnvFile)) { Fail "Env file not found: $EnvFile" }
$EnvFile = (Resolve-Path -LiteralPath $EnvFile).Path
Read-EnvFile $EnvFile

function Get-Cfg([string]$k, [string]$default = "") {
    if ($script:Cfg.Contains($k) -and -not [string]::IsNullOrWhiteSpace([string]$script:Cfg[$k])) { return [string]$script:Cfg[$k] }
    return $default
}
function Get-Bool([string]$k, [bool]$default) {
    $v = (Get-Cfg $k "").ToLowerInvariant()
    if ($v -eq "") { return $default }
    return @("true", "1", "yes", "y", "on") -contains $v
}

$RepoRoot     = $script:RepoRootResolved
$InfraDir     = ConvertTo-WinPath (Get-Cfg "INFRA_DIR" (Join-Path $RepoRoot "infra"))
$AppsDir      = ConvertTo-WinPath (Get-Cfg "APPS_DIR" (Join-Path $RepoRoot "apps"))
$StateDir     = ConvertTo-WinPath (Get-Cfg "STATE_DIR" (Join-Path $RepoRoot ".state"))
$ArtifactsDir = ConvertTo-WinPath (Get-Cfg "ARTIFACTS_DIR" (Join-Path $StateDir "artifacts"))
$BackendCfg   = Get-Cfg "TF_BACKEND_CONFIG" ""
if ($BackendCfg -ne "") { $BackendCfg = ConvertTo-WinPath $BackendCfg }
$TfVarsFile   = Join-Path $StateDir "terraform.tfvars.json"
$PlanFile     = Join-Path $StateDir "tfplan"
$StateFile    = Join-Path $StateDir "terraform.tfstate"
$AutoApprove  = $Yes -or (Get-Bool "AUTO_APPROVE" $false)
$AwsProfile   = Get-Cfg "AWS_PROFILE" ""
$AwsRegion    = Get-Cfg "AWS_REGION" "us-east-1"
$AccountId    = Get-Cfg "AWS_ACCOUNT_ID" ""
$Prefix       = Get-Cfg "PROJECT_PREFIX" "nimbus-demo-lite"
$TfBin        = Get-Cfg "TERRAFORM_BIN" "terraform"
$AwsBin       = Get-Cfg "AWS_BIN" "aws"
if ($TfBin -ne "terraform") { $TfBin = ConvertTo-WinPath $TfBin }
if ($AwsBin -ne "aws") { $AwsBin = ConvertTo-WinPath $AwsBin }

# Terraform working data lives under STATE_DIR so the repo stays clean.
$env:TF_DATA_DIR = Join-Path $StateDir ".terraform"
$env:TF_IN_AUTOMATION = "1"
$env:AWS_REGION = $AwsRegion
$env:AWS_DEFAULT_REGION = $AwsRegion
if ($AwsProfile -ne "") { $env:AWS_PROFILE = $AwsProfile }

function Invoke-Tool([string]$exe, [string[]]$toolArgs, [string]$cwd = $InfraDir) {
    Push-Location -LiteralPath $cwd
    try {
        & $exe @toolArgs
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    if ($code -ne 0) { Fail "$exe $($toolArgs -join ' ') exited with code $code" }
}

function Test-Tool([string]$exe) { return [bool](Get-Command $exe -ErrorAction SilentlyContinue) }

# ------------------------------------------------------------------ commands
function Invoke-Preflight {
    Write-Step "preflight ($(if ($Offline) {'offline'} else {'live'}))"
    Write-Ok "env file  : $EnvFile"
    Write-Ok "REPO_ROOT : $RepoRoot"
    foreach ($pair in @(@("INFRA_DIR", $InfraDir), @("APPS_DIR", $AppsDir))) {
        if (-not (Test-Path -LiteralPath $pair[1])) { Fail "$($pair[0]) not found: $($pair[1])" }
        Write-Ok ("{0,-9} : {1}" -f $pair[0], $pair[1])
    }
    Write-Ok "STATE_DIR : $StateDir"
    if (-not (Test-Tool $TfBin)) { Fail "terraform not found. Install: winget install Hashicorp.Terraform" }
    $tfv = (& $TfBin version -json | ConvertFrom-Json).terraform_version
    if ([version]$tfv -lt [version]"1.6.0") { Fail "Terraform >= 1.6.0 required (found $tfv)" }
    Write-Ok "terraform $tfv"

    if (-not (Test-Path -LiteralPath (Join-Path $AppsDir "webhooks\webhook_receiver.py"))) { Fail "apps\webhooks\webhook_receiver.py missing under APPS_DIR" }
    $cidr = Get-Cfg "ALLOWED_CIDR" "0.0.0.0/0"
    if ($cidr -notmatch '^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$') { Fail "ALLOWED_CIDR '$cidr' is not an IPv4 CIDR" }
    if ($cidr -eq "0.0.0.0/0") { Write-Warn2 "ALLOWED_CIDR is 0.0.0.0/0 - weak demo endpoints are open to the internet (synthetic data only)" }
    if ($Prefix -notmatch '^[a-z][a-z0-9-]{2,24}$') { Fail "PROJECT_PREFIX must be 3-25 chars of lowercase letters, digits, hyphens" }

    if ($Offline) { Write-Ok "offline mode: skipping AWS account checks"; return }

    if ($AccountId -notmatch '^\d{12}$') { Fail "AWS_ACCOUNT_ID must be a 12-digit account id (got '$AccountId')" }
    if ($AccountId -eq "123456789012") { Fail "AWS_ACCOUNT_ID is still the sample value 123456789012 - set your real account id in deploy.env" }
    $email = Get-Cfg "OWNER_EMAIL" ""
    if ((Get-Bool "ENABLE_BUDGET" $true) -and ($email -eq "" -or $email -like "*@example.com")) { Fail "OWNER_EMAIL is empty or still the example.com sample" }
    if ((Get-Cfg "BUCKET_SUFFIX" "") -match '123456789012') { Fail "BUCKET_SUFFIX still contains the sample account id" }
    if (-not (Test-Tool $AwsBin)) { Fail "AWS CLI not found. Install: winget install Amazon.AWSCLI" }
    Write-Ok ("aws cli: " + ((& $AwsBin --version) -join ' '))
    $actual = & $AwsBin sts get-caller-identity --query Account --output text 2>&1
    if ($LASTEXITCODE -ne 0) { Fail "aws sts get-caller-identity failed (profile '$AwsProfile'). Run: aws sso login --profile $AwsProfile`n$actual" }
    $actual = ([string]$actual).Trim()
    if ($actual -ne $AccountId) { Fail "Credentials are for account $actual but AWS_ACCOUNT_ID is $AccountId - refusing to continue" }
    Write-Ok "AWS account $actual matches AWS_ACCOUNT_ID (region $AwsRegion)"
}

function Invoke-RenderVars {
    Write-Step "render-vars -> $TfVarsFile"
    New-Item -ItemType Directory -Force -Path $StateDir, $ArtifactsDir | Out-Null
    $budget = 50
    [void][double]::TryParse((Get-Cfg "MONTHLY_BUDGET_USD" "50"), [ref]$budget)
    $vars = [ordered]@{
        project_prefix         = $Prefix
        aws_region             = $AwsRegion
        aws_account_id         = $(if ($Offline) { "" } else { $AccountId })
        owner_email            = Get-Cfg "OWNER_EMAIL" "ops@example.com"
        bucket_suffix          = Get-Cfg "BUCKET_SUFFIX" "-demo"
        cognito_domain_prefix  = Get-Cfg "COGNITO_DOMAIN_PREFIX" "$Prefix-auth"
        instance_type          = Get-Cfg "INSTANCE_TYPE" "t3.small"
        db_instance_class      = Get-Cfg "DB_INSTANCE_CLASS" "db.t4g.micro"
        enable_budget          = Get-Bool "ENABLE_BUDGET" $true
        monthly_budget_usd     = $budget
        allowed_cidr           = Get-Cfg "ALLOWED_CIDR" "0.0.0.0/0"
        enable_legacy_exposure = Get-Bool "ENABLE_LEGACY_EXPOSURE" $true
        pq_key_spec            = Get-Cfg "PQ_KEY_SPEC" "ML_DSA_65"
        apps_dir               = ConvertTo-TfPath $AppsDir
        artifacts_dir          = ConvertTo-TfPath $ArtifactsDir
    }
    $json = $vars | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($TfVarsFile, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok "wrote $($vars.Count) variables"
}

function Invoke-Init([bool]$noBackend) {
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    $a = @("init", "-input=false", "-no-color")
    if ($noBackend) { $a += "-backend=false" }
    elseif ($BackendCfg -ne "") { $a += @("-reconfigure", "-backend-config=$BackendCfg") }
    else { $a += @("-reconfigure", "-backend-config=path=$(ConvertTo-TfPath $StateFile)") }
    Invoke-Tool $TfBin $a
}

function Invoke-Validate {
    Write-Step "validate (terraform init -backend=false, fmt -check, validate)"
    Invoke-Init $true
    Invoke-Tool $TfBin @("fmt", "-check", "-recursive", "-diff")
    Write-Ok "terraform fmt -check"
    Invoke-Tool $TfBin @("validate", "-no-color")
    Write-Ok "terraform validate"
}

function Invoke-Plan {
    if ($Offline) { Fail "plan needs AWS access; drop -Offline" }
    Invoke-RenderVars
    Write-Step "plan"
    Invoke-Init $false
    Invoke-Tool $TfBin @("plan", "-input=false", "-var-file=$(ConvertTo-TfPath $TfVarsFile)", "-out=$(ConvertTo-TfPath $PlanFile)")
    Write-Ok "plan saved to $PlanFile"
}

function Invoke-Outputs {
    if ($Offline) { Fail "outputs reads state; drop -Offline" }
    Write-Step "outputs"
    Invoke-Init $false
    Invoke-Tool $TfBin @("output")
    $json = & $TfBin "-chdir=$InfraDir" output -json
    if ($LASTEXITCODE -eq 0) {
        [System.IO.File]::WriteAllText((Join-Path $StateDir "outputs.json"), ($json -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
        Write-Ok "saved $(Join-Path $StateDir 'outputs.json')"
    }
}

function Invoke-Deploy {
    if ($Offline) { Fail "deploy needs AWS access; drop -Offline" }
    Invoke-Preflight
    Invoke-RenderVars
    Write-Step "deploy (terraform apply)"
    Invoke-Init $false
    $a = @("apply", "-input=false", "-var-file=$(ConvertTo-TfPath $TfVarsFile)")
    if ($AutoApprove) { $a += "-auto-approve" }
    Invoke-Tool $TfBin $a
    Invoke-Outputs
    Write-Host ""
    Write-Host "Deployed. The EC2 host needs ~5 minutes after apply to install Docker and start containers." -ForegroundColor Green
    Write-Host "Shell access: aws ssm start-session --target <ec2_instance_id>" -ForegroundColor Green
}

function Invoke-Destroy {
    if ($Offline) { Fail "destroy needs AWS access; drop -Offline" }
    Invoke-Preflight
    Invoke-RenderVars
    if (-not $AutoApprove) {
        $answer = Read-Host "Type the project prefix '$Prefix' to DESTROY everything in account $AccountId"
        if ($answer -ne $Prefix) { Fail "destroy cancelled" }
    }
    Write-Step "destroy (terraform destroy)"
    Invoke-Init $false
    Invoke-Tool $TfBin @("destroy", "-input=false", "-auto-approve", "-var-file=$(ConvertTo-TfPath $TfVarsFile)")
    Write-Ok "all resources destroyed (state kept in $StateDir)"
}

function Show-Help {
    @"
nimbus-demo-lite deployer (PowerShell)

Usage: .\deploy.ps1 [-Offline] [-Yes] [-EnvFile <path>] <command> [<command> ...]

Commands:
  preflight    check tools, paths and (unless -Offline) that AWS creds match AWS_ACCOUNT_ID
  render-vars  write STATE_DIR\terraform.tfvars.json from deploy.env
  validate     terraform init -backend=false + fmt -check + validate (no AWS needed)
  plan         terraform plan (saved to STATE_DIR\tfplan)
  deploy       preflight + render-vars + terraform apply + outputs   (alias: all)
  outputs      print endpoints and save STATE_DIR\outputs.json
  destroy      terraform destroy (asks you to type the project prefix unless -Yes)
"@ | Write-Host
}

foreach ($c in $cmdList) {
    switch ($c) {
        "preflight"   { Invoke-Preflight }
        "render-vars" { Invoke-RenderVars }
        "validate"    { Invoke-Validate }
        "plan"        { Invoke-Plan }
        "deploy"      { Invoke-Deploy }
        "all"         { Invoke-Deploy }
        "apply"       { Invoke-Deploy }
        "outputs"     { Invoke-Outputs }
        "destroy"     { Invoke-Destroy }
        "help"        { Show-Help }
        default       { Show-Help; Fail "unknown command '$c'" }
    }
}
Write-Host "Done: $($cmdList -join ', ')" -ForegroundColor Green
