project "LuaJIT"
	kind "Makefile"

	buildcommands { "cd ../vendor/luajit && make clean && make" }
	rebuildcommands { "cd ../vendor/luajit && make clean && make" }
	cleancommands { "cd ../vendor/luajit && make clean" }
