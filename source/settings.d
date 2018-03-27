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

string get_option(Options o) {
	switch (o) {
		case Options.None:
			return "none";
		case Options.Zoom:
			return "zoom";
		case Options.Wallpaper:
			return "wallpaper";
		case Options.Stretched:
			return "stretched";
		case Options.Spanned:
			return "spanned";
		case Options.Scaled:
			return "scaled";
		case Options.Centered:
			return "centered";
		default:
			return "none";
	}
}

enum Options {
	None = 0,
	Wallpaper = 1,
	Centered = 2,
	Scaled = 3,
	Stretched = 4,
	Zoom = 5,
	Spanned = 6
}

class Settings {
	mixin JsonizeMe;

	public @jsonize bool legacy;
	public @jsonize bool use_clock_intervals;
	public @jsonize int timeout;
	public @jsonize Options default_option;
	public @jsonize Wallpaper[] wallpapers;
}

class Wallpaper {
	mixin JsonizeMe;

	this(Options option, string file, string time) {
		this.option = option;
		this.file = file;
		this.time = time;
	}

	this() {

	}

	public @jsonize Options option;
	public @jsonize string file;
	public @jsonize string time;

	public @property TimeOfDay clock_offset() {
		return TimeOfDay.fromISOExtString(time);
	}
}