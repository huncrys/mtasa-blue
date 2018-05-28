project "LuaJIT"
	kind "Makefile"

	buildcommands { "cd ../vendor/luajit && make clean && make" }
	rebuildcommands { "cd ../vendor/luaji && make clean && make" }
	cleancommands { "cd ../vendor/luajit && make clean" }
