# MIDI Player

A window in the guitar menu that plays **MIDI files** on your guitar by itself.

*This mod was created with the assistance of AI.*

- Client side only: nothing to install on the server, and it works on any server. The other players hear it like a song you play by hand.
- Needs no MIDI device, no loopMIDI and no program running next to the game.

## How to use

1. Open the guitar menu (use the guitar as usual). The **MIDI Player** window is in the middle of the screen.
2. **Import...** and pick one or more `.mid` files. You can also drop `.mid` files onto the game window while the guitar menu is open, or put them in the mod's folder (**Open folder** shows it).
3. Click a song, then **Play** (or double-click the song). The fret markers on the guitar follow the notes.

The window can be dragged by its title and folded with the **-** button. Your song list and settings are kept between sessions.

## The window

- **List:** every imported song with its length. Imported files are copied into the mod's folder; your originals are not touched. **Remove** deletes the copy (it asks "Sure?" first).
- **Play / Pause, Stop, << >>** (previous / next song), a position slider, and **Repeat:** off, one song, or all songs.
- **Speed** 50% to 150%.
- **Pitch** - / + moves the whole song by semitones.
- **Fit the song to the guitar's range** (on by default) shifts the whole song up or down by octaves so as many notes as possible can be played.
- **Tracks to play:** a MIDI file has several tracks (melody, bass, chords, ...). Switch tracks off to leave things out. Drums are always skipped.

The window shows how many notes of the song are played and why some are not.

## What the guitar can do

The game's guitar has 6 strings and frets 0-15, which covers the notes E2 to G5 (MIDI 40 to 79). The mod picks a string and fret for every note:

- Notes outside that range are moved by whole octaves so they keep their note name.
- Notes that start together (chords) go on different strings. More than 6 at once is too many: the highest, the lowest and the loudest are kept.
- A string plays one note at a time, so the mod avoids cutting a note that is still held when another string is free.
- At most 48 notes a second are sent (every note goes to all players over the network).

Songs with one or two clear instruments (a melody with a bass line) sound best. For a busy song, try switching tracks off.

## Good to know

- Playing stops when you close the guitar menu.
- You can still play by hand while a song plays. Your saved chord shapes are never changed.
- Files up to 3 MB, up to 500 songs. A file that is not a MIDI file is refused with a message.
- The mod does not use MIDI input devices, so it can sit next to mods that do (not tested together).

## Install

Install with a mod manager (needs **GDWeave**), or put the `MIDIPlayer` folder from the zip into `GDWeave/mods`.

## License

MIT. Anyone may copy, change and make their own version.
