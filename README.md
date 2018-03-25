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
    "wallpapers": [
        "/path/to/image1",
        "/path/to/image2",
        "/path/to/image3",
        "/path/to/image4",
        "/path/to/etc/etc",
    ]
}
```

The timeout variable is the time between updates in seconds.
