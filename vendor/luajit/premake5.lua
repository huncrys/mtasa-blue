project "LuaJIT"
	kind "Makefile"

	local luajit_make = "@+${MAKE} -C ../vendor/luajit"
	if os.getenv("LUAJIT_CC") then
		luajit_make = luajit_make .. " CC=" .. os.getenv("LUAJIT_CC")
	end
	if _OPTIONS["gccprefix"] then
		luajit_make = luajit_make .. " CROSS=" .. _OPTIONS["gccprefix"]
	end
	buildcommands { luajit_make }
	rebuildcommands { 
		luajit_make .. " clean",
		luajit_make
	}
	cleancommands { luajit_make .. " clean" }
