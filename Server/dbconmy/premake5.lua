project "Dbconmy"
	language "C++"
	kind "SharedLib"
	targetname "dbconmy"
	targetdir(buildpath("server/mods/deathmatch"))

	filter "system:windows"
		includedirs {
			"../../vendor/mysql/include",
			"../../vendor/sparsehash/src/windows"
		}

	filter {}
		includedirs {
			"../../Shared/sdk",
			"../sdk",
			"../../vendor/google-breakpad/src",
			"../../vendor/sparsehash/src/"
		}

	pchheader "StdInc.h"
	pchsource "StdInc.cpp"

	vpaths {
		["Headers/*"] = "**.h",
		["Sources"] = "*.c",
		["*"] = "premake5.lua"
	}

	files {
		"premake5.lua",
		"*.h",
		"*.cpp"
	}

	filter "system:linux"
		includedirs { "/usr/include/mysql" }
		links { "rt" }

	filter "system:macosx"
		includedirs {
			os.findheader("mysql.h", {
				"/usr/local/opt/mysql/include/mysql",
				"/opt/homebrew/include/mysql",
				"/opt/osxcross/macports/pkgs/opt/local/include/mysql8/mysql",
			})
		}
		libdirs {
			os.findlib("libmysqlclient.a", {
				"/usr/local/opt/mysql/lib",
				"/opt/homebrew/lib",
				"/opt/osxcross/macports/pkgs/opt/local/lib/mysql8/mysql",
			})
		}

	-- Always link libmysqlclient statically on Linux: distributions have moved to
	-- MariaDB, so libmysqlclient.so.21 (and its versioned symbols) is not
	-- available at runtime on a modern base image. OpenSSL stays dynamic.
	--
	-- The static archive carries no dependency information, so every library it
	-- needs has to be named here. zstd is the easy one to miss: MySQL 8 uses it for
	-- protocol compression, and because this is a shared library the linker leaves
	-- ZSTD_* undefined without complaint - it only surfaces as a dlopen failure
	-- when the server loads dbconmy.so.
	filter "system:linux"
		buildoptions { "-pthread" }
		linkoptions { "-l:libmysqlclient.a", "-pthread", "-lssl", "-lcrypto" }
		links { "z", "zstd", "dl", "m" }
	filter { "system:linux", "platforms:x86" }
		libdirs { "/usr/lib32/mysql" }
	filter { "system:linux", "platforms:x64" }
		libdirs { "/usr/lib64/mysql" }

	filter "system:macosx"
		links { "mysqlclient" }

	filter { "system:windows", "platforms:x64" }
		links { "../../vendor/mysql/lib/x64/libmysql.lib" }
	filter { "system:windows", "platforms:x86" }
		links { "../../vendor/mysql/lib/x86/libmysql.lib" }
	filter { "system:windows", "platforms:arm64" }
		links { "../../vendor/mysql/lib/arm64/libmysql.lib" }

	filter "platforms:x64"
		targetdir(buildpath("server/x64"))

	filter "platforms:arm"
		targetdir(buildpath("server/arm"))

	filter "platforms:arm64"
		targetdir(buildpath("server/arm64"))
