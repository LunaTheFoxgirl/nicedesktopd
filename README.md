# nicedesktopd
A small application meant to be used as a wallpaper setting daemon for linux. Written in D.

## Building
Install a distribution of dlang including dub using **D 2**.

Once you have that, run `dub` in the repository.

It will try launching the application but it will fail at doing anything until a configuration file has been made.

You can now Ctrl+C out of the program, and copy it over to an path you want to run it from.

Add `~/.config/nicewallpaperd.json` if it does not currently exist and add the following:

```json
{
    "timeout": 20,
	"legacy": false,
    "wallpapers": [
        "/path/to/foo",
        "/path/to/bar",
        "/path/to/etc/etc"
    ]
}
```

The timeout variable is the time between updates in seconds.

Replace the placeholders in the wallpapers section with the path to each file you want to cycle between.

### NOTICE
If you are running a unity desktop, the desktop might go to a state where it shows the stock background, setting legacy to `true` tends to fix this.

## DBus Documentation

### Basics
The router is located at `dk.eclipsingr.nice`.

The object path is `/wallpaper`, with interfaces in `dk.eclipsingr.nice.wallpaper`

### Layout
* `dk.eclipsingr.nice`
    * `/wallpaper`
        * `dk.eclipsingr.nice.wallpaper`
            * `current()` - Gets current image used as wallpaper
            * `list()` - Gets list of wallpapers cycled between
            * `timeout()` - Gets the timeout between wallpaper advances in seconds.
            * `next()` - Advances to next image.
            * `previous()` - Goes to previous image.
            * `set_advance_time(int seconds)` - Sets the timeout between wallpaper advances in seconds.
            * `set_wallpaper_list(string[] wallpapers)` - Sets the list of wallpapers to cycle between.
