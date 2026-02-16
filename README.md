## Abstract
This is by **NO MEANS** code for tmux/psmux or anything to that effect. Calling this a poor man's or bootleg version of them is already an overstatement. Being a victim of circumstance, there was no access to any of the mentioned tools or their installers so this repo came into existence out of absurd delusions. The code does not multiplex your terminal and does not have persistence, but instead naively and rather ludicrously spawns N windows, and M panes per window or N*M backgrounded terminals to run the target script that you point them to. Making your target script concurrent is definitely the better option, but if shoddy process concurrency across windows/background processes is somehow more your tempo, this is the way to go.

## Additional Details
The venv flag that is used currently only accepts venv from cmd, and the script itself is run on a windows machine using git bash.

## Setting Up
Clone the repo into a directory of your liking
```
git clone https://github.com/NomadicSasquatch/Poor-Mans-Bootleg-tmux.git
```
Set up your venv (in cmd for now)
```
python -m venv venv
```
Change/set the .env variables for your script
