# Setting up a Windows testing and review machine

Use a Hyper-V virtual machine to test ports and run the
[`review-vcpkg-prs-today` skill](../../.github/skills/review-vcpkg-prs-today/SKILL.md)
in an environment approximating the Windows build lab.

The lab image is built by [`windows/create-image.ps1`](windows/create-image.ps1).
This guide uses the same provisioning scripts, but installs Windows Server locally
instead of creating an Azure VM. The Azure image uses Windows Server 2025 Datacenter
Azure Edition; an ISO-based Hyper-V installation is not an exact copy of that image.
Use the provisioning scripts from the repository revision corresponding to the lab
image you want to reproduce.

## Prepare the build-lab baseline

### 1. Get Hyper-V working on the host

Enable hardware virtualization in the host's firmware and install Hyper-V on a
supported Windows edition. In an elevated PowerShell session on a Windows client
host, run:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
```

On a Windows Server host, use this instead:

```powershell
Install-WindowsFeature -Name Hyper-V -IncludeManagementTools -Restart
```

Restart if required, then open Hyper-V Manager and configure a virtual switch that
gives the guest internet access. The provisioning scripts download installers.
Allocate sufficient memory, CPU, and disk space for Visual Studio, CUDA, and concurrent
port builds. For reference, the lab image creation script uses `Standard_D8ads_v5`.

### 2. Install Windows Server 2025

Get a Windows Server 2025 installation ISO from
[Visual Studio Downloads](https://my.visualstudio.com/Downloads/Featured).
Create a Generation 2 VM, attach the ISO, and install Windows Server 2025 with
**Desktop Experience** so that VS Code and interactive authentication are available.

Finish Windows setup, install updates, and verify that the guest can access the
internet. Use an administrator account for provisioning.

### 3. Optionally disable Shutdown Event Tracker and uninstall Windows Defender

These changes are optional conveniences for a disposable testing VM, not requirements
for running reviews. Removing Defender reduces protection; do not do this on the host,
and follow your organization's security policy.

To disable Shutdown Event Tracker, open `gpedit.msc` in the guest and set
**Computer Configuration > Administrative Templates > System > Display Shutdown
Event Tracker** to **Disabled**.

To uninstall Windows Defender, run in an elevated PowerShell session in the guest:

```powershell
Uninstall-WindowsFeature -Name Windows-Defender
```

Restart the guest if required.

### 4. Copy the provisioning directory into the VM

Copy the entire [`windows` directory](windows), including its supporting files, from
`scripts\azure-pipelines\windows` into the guest, for example to `C:\provision\windows`.
Do not copy only the entry-point script.

One way to transfer the files is to create a separate VHDX on the host, initialize and
format it, and copy the directory onto it. Dismount the VHDX from the host before
attaching it to the VM. In the guest, bring the disk online if necessary and copy the
directory to the guest's system disk. Detach the transfer disk when finished. A network
share or another file-transfer mechanism is also fine.

### 5. Run the provisioning script

In an elevated PowerShell session in the guest:

```powershell
Set-Location C:\provision\windows
.\provision-entire-image.ps1
```

If execution policy blocks the scripts, and your organization's policy permits it,
allow them for this session only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\provision-entire-image.ps1
```

[`provision-entire-image.ps1`](windows/provision-entire-image.ps1) installs the build
tools and applies the settings used by the lab image. Local provisioning downloads
assets from their upstream sources rather than using the Azure image-minting managed
identity. Check the output for installation failures and resolve them before continuing.
Restart after provisioning to complete any pending installations.

### 6. Create a checkpoint

Shut down the guest and create a checkpoint in Hyper-V Manager, for example named
`Provisioned build-lab baseline`. This is the clean baseline to restore before testing.
The guest now has the build-tool provisioning used by the lab, subject to the OS and
Azure differences described above.

Create this checkpoint **before** adding personal SSH keys or signing in to services.
Do not share or export a personalized VM or checkpoint containing credentials.

## Set up the review account and tools

Start the guest again. Run the following setup as the account that will perform reviews;
Git's global configuration and authentication are per-user.

### Configure Git identity and optional SSH signing

Use your real name and email address, not the example identity of another reviewer:

```powershell
git config --global user.name "Your Real Name"
git config --global user.email "you@example.com"
```

If you use SSH signing, securely copy the required SSH keys into this account's
`$env:USERPROFILE\.ssh` directory and protect the private key. Configure signing using
the public key that corresponds to your signing key:

```powershell
git config --global gpg.format ssh
git config --global commit.gpgsign true
git config --global user.signingkey (Join-Path $env:USERPROFILE '.ssh\id_rsa.pub')
```

Replace `id_rsa.pub` if your key has a different filename. The equivalent signing-key
command in **Command Prompt**, not PowerShell, is:

```cmd
git config --global user.signingkey "%USERPROFILE%\.ssh\id_rsa.pub"
```

For GitHub to verify signatures, register the public key as a signing key in your
GitHub account.

### Install VS Code and authenticate GitHub Copilot

Download [VS Code](https://code.visualstudio.com/Download) and choose the Windows
**System Installer**, rather than the User Installer. Install it in the guest, then
enable GitHub Copilot and sign in with the account that has Copilot access. Use the
device-code authentication flow and complete authorization in a browser, on the host
if needed. Confirm that Copilot Chat works before starting reviews.

### Install GitHub CLI and ripgrep

In the guest:

```powershell
winget install GitHub.CLI
winget install BurntSushi.RipGrep.MSVC
```

Authenticate GitHub CLI separately from Copilot:

```powershell
gh auth login --hostname github.com --web
gh auth status
```

Follow the device-code instructions, completing authorization in a browser. Choose
the Git protocol appropriate for your account; SSH commit signing does not require
using SSH as the Git transport.

### Get vcpkg and run reviews

Clone vcpkg to a short path on a disk with room for builds and review workspaces:

```powershell
git clone https://github.com/microsoft/vcpkg.git C:\vcpkg
Set-Location C:\vcpkg
.\bootstrap-vcpkg.bat
gh auth status
rg --version
code .
```

In VS Code, invoke the repository's `review-vcpkg-prs-today` skill, for example:

```text
/review-vcpkg-prs-today investigation-root C:\vcpkg-prs
```

Keep the investigation root on the same drive as the checkout with a short path.
The skill creates isolated review workspaces and writes final reports under the
caller's `reviews` directory. See the
[skill instructions](../../.github/skills/review-vcpkg-prs-today/SKILL.md) for review
depth options, including building consumer examples.

After restoring the clean baseline checkpoint, repeat the account and review-tool
setup before running reviews.
