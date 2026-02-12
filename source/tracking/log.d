module tracking.log;

import std.format : format;
import std.stdio : writeln;

void insLogInfo(T...)(string msg, T args) {
    writeln("[tracking][info] " ~ msg.format(args));
}

void insLogErr(T...)(string msg, T args) {
    writeln("[tracking][error] " ~ msg.format(args));
}



