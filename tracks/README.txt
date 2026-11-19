Half-Life 2: Kart - the dedicated server's tracks folder

Put custom tracks (.hl2kt files saved by the TRACK EDITOR) here and a dedicated server
races them. Name one in server.cfg by its file name without .hl2kt, its name, its c_ id
or the first letters of its hash:

    mp_track canal_run
    mp_tracklist "canal_run, xen, Old Docks"
    mp_rotate 1

The server also looks in the folder named by sv_tracks (or --tracks <dir>), in a tracks
folder next to the game executable and in its own user://tracks folder (never in its
hidden .autosave, .trash or .history folders, nor in cache). Every file is checked when
the server starts; a damaged one is skipped with a line in the log. Players who do not
have the track download it in the lobby (sv_downloads 0 turns them away instead).

The game ignores this folder (.gdignore) and git keeps only this file: the tracks you put
here stay on your computer.
