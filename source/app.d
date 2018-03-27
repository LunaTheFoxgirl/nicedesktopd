import syscalld : syscall, GETUID;
import std.stdio;
import ddbus;
import ddbus.c_lib;
import handlers;

void main() {
	//Establish connection to DBus.
	Connection conn = connectToBus();

	//Set up message router.
	MessageRouter router = new MessageRouter();

	//Setup handler
	int uid = cast(int)syscall(GETUID);
	Handlers handler = new Handlers(uid);

	//Register methods
	registerMethods(router, "/dk/eclipsingr/nice/wallpaper", "dk.eclipsingr.nice.wallpaper", handler);

	//Register router and run loop.
	writeln("<INFO> Starting from UID ", uid, "...");

	registerRouter(conn, router);
	bool gotem = requestName(conn, "dk.eclipsingr.nice");
	while (true) {
		conn.tick();
	}
}