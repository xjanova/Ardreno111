# Engineer Setup Guide — Arduino Auto-Deploy

This system automatically uploads Arduino code to your board whenever new code is pushed to GitHub.
**You only need to set this up once.**

---

## What You Need

- Windows PC (stays on or turns on during work hours)
- Arduino board (Uno, Nano, Mega, etc.)
- USB cable that **transfers data** (not charge-only)
- Internet connection
- GitHub account (ask the team if you don't have one)

---

## Setup (One Time Only)

### Step 1: Plug in Arduino

Connect your Arduino to the PC with the USB cable.

### Step 2: Download the project

**Option A — If you have Git:**

```powershell
cd D:\Code
git clone https://github.com/xjanova/Ardreno111.git
cd Ardreno111
```

**Option B — If you don't have Git:**

1. Go to https://github.com/xjanova/Ardreno111
2. Click green **Code** button → **Download ZIP**
3. Extract to `D:\Code\Ardrino111`

### Step 3: Run the installer

1. Right-click the **Start** button → select **Terminal (Admin)** or **PowerShell (Admin)**
2. Run:

```powershell
cd D:\Code\Ardrino111
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install_runner.ps1
```

3. Wait — the script installs everything automatically
4. **When the browser opens** → log in to GitHub → click **Authorize**
5. Wait until you see:

```
==================================================
  INSTALLATION COMPLETE!
==================================================
```

### Step 4: Done

There is no Step 4. Everything is set up.

---

## After Setup — How It Works

```
Programmer pushes code to GitHub
        ↓
Your PC automatically receives the update
        ↓
Code compiles and uploads to Arduino
        ↓
Arduino runs the new code (LED blinks, motor moves, etc.)
```

**You don't need to do anything.** The system works in the background 24/7.

---

## What Happens In Different Situations

| Situation | What to do |
|-----------|-----------|
| PC restarts | Nothing — the runner starts automatically |
| New code pushed | Nothing — Arduino updates automatically |
| Move USB to different port | Nothing — system auto-detects the new port |
| Swap to a different Arduino | Nothing — system auto-detects the new board |
| Want to check status | Open https://github.com/xjanova/Ardreno111/actions |
| Something seems wrong | Run `.\check_deploy.ps1` in PowerShell |

---

## Troubleshooting

### Check if Arduino is connected

```powershell
arduino-cli board list
```

You should see your board (e.g. `Arduino Uno` on `COM3`). If you see nothing:
- Try a different USB cable (some cables are charge-only)
- Try a different USB port
- Check Windows Device Manager → Ports (COM & LPT)

### Test manually

```powershell
.\deploy.ps1
```

This compiles and uploads the test sketch directly without going through GitHub.

### Check recent deploy status

```powershell
.\check_deploy.ps1           # Latest run
.\check_deploy.ps1 -List 5   # Last 5 runs
.\check_deploy.ps1 -Full     # Full log
```

### Runner not working

1. Open **Task Manager** → **Services** tab
2. Look for a service starting with `actions.runner.`
3. If stopped, right-click → **Start**

Or re-run the installer:

```powershell
.\install_runner.ps1
```

---

## Important: Do NOT

- **Don't** close the runner service in Task Manager
- **Don't** unplug USB while the Arduino LED is flashing rapidly (uploading)
- **Don't** keep Arduino IDE Serial Monitor open (it locks the COM port)
- **Don't** delete the `C:\actions-runner` folder

---

## Need Help?

- Check deploy status: https://github.com/xjanova/Ardreno111/actions
- Contact the programmer — they can see all error logs on GitHub
