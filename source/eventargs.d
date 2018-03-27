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

import settings;

class AddWallpaperEventArgs : EventArgs {
	public Options option;
	public string file;
	public TimeOfDay clock_offset;

	this(Options option, string file, TimeOfDay clock_offset) {
		this.option = option;
		this.file = file;
		this.clock_offset = clock_offset;
	}
}

class RemoveWallpaperEventArgs : EventArgs {
	public string file;

	this(string file) {
		this.file = file;
	}
}

class SetWallpaperOptionsEventArgs : EventArgs {
	public Options option;

	this(Options option) {
		this.option = option;
	}
}


class SetWallpaperUpdateEventArgs : EventArgs {
	public int time;

	this (int time) {
		this.time = time;
	}
}