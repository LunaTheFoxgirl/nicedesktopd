import syscalld : syscall, GETUID;
import sev.event;
import jsonizer;
import ddbus;
import ddbus.c_lib;

import core.thread;
import core.time;

import std.stdio;
import std.conv;
import std.json;
import std.datetime;

import controller;
import settings;
import eventargs;

class Handlers {
	private Controller controller;

	this(int uid) {
		this.controller = new Controller(uid);
		this.OnNextWallpaper += &controller.NextWallpaper;
		this.OnPrevWallpaper += &controller.PreviousWallpaper;

		this.OnAddWallpaper += &controller.AddWallpaper;
		this.OnRemoveWallpaper += &controller.RemoveWallpaper;
		this.OnClearWallpapers += &controller.ClearWallpapers;

		this.OnSetUpdateTime += &controller.SetUpdateTime;
		this.OnSetWallpaperOptions += &controller.SetWallpaperOptions;
		this.controller.Start();
	}

	public Event OnNextWallpaper = new Event();
	public Event OnPrevWallpaper = new Event();
	public Event OnAddWallpaper = new Event();
	public Event OnRemoveWallpaper = new Event();
	public Event OnClearWallpapers = new Event();
	public Event OnSetUpdateTime = new Event();
	public Event OnSetWallpaperOptions = new Event();

	public string next() {
		OnNextWallpaper(null, null);
		return current();
	}

	public string previous() {
		OnPrevWallpaper(null, null);
		return current();
	}

	public string current() {
		return this.controller.wallpapers[this.controller.current_wallpaper].file;
	}

	public Wallpaper[] list() {
		return this.controller.wallpapers;
	}

	public int timeout() {
		return this.controller.timeout;
	}

	public void clear_wallpapers() {
		OnClearWallpapers(cast(void*)this, null);
	}

	public string set_update_time(int seconds) {
		try {
			OnSetUpdateTime(cast(void*)this, new SetWallpaperUpdateEventArgs(seconds));
			return "success";
		} catch (Exception ex) {
			writeln(ex);
			return ex.message.text;
		}
	}

	public string set_wallpaper_option(int option) {
		try {
			ubyte o = cast(ubyte)option;
			if (o > 6) o = 7;
			if (o < 0) o = 0;

			OnSetWallpaperOptions(cast(void*)this, new SetWallpaperOptionsEventArgs(cast(Options)o));
			return "success: " ~ get_option(cast(Options)o);
		} catch (Exception ex) {
			return ex.message.text;
		}
	}

	public string add_wallpaper(string file, int option, string offset_time) {
		try {
			ubyte o = cast(ubyte)option;
			if (o > 6) o = 7;
			if (o < 0) o = 0;
			TimeOfDay st = TimeOfDay.fromISOExtString(offset_time);
			OnAddWallpaper(cast(void*)this, new AddWallpaperEventArgs(cast(Options)o, file, st));
			return "success";
		} catch (Exception ex) {
			return ex.message.text;
		}
	}

	public string remove_wallpaper(string file) {
		try {
			OnRemoveWallpaper(cast(void*)this, new RemoveWallpaperEventArgs(file));
			return "success";
		} catch (Exception ex) {
			return ex.message.text;
		}
	}
}