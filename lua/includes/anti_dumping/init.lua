
local STRING_TYPE = "string"
local LUA_VFS = "LUA"
local LUA_VFS_PATTERN = "^lua%/"
local LUA_VFS_CLIENT_AUTORUN_PATTERN = "^lua%/autorun%/client"
local FILE_PATH_PATTERN = "^(.*[/\\])[^/\\]-$"
local FILE_PATH_SEPARATOR = "/"
local EMPTY_STRING = ""
local ONLY_NEWLINES_PATTERN = "[^\n]"

local SUFFIX_IDX = (system.IsWindows() and 4 or 0) + (system.IsLinux() and 2 or 0) + (jit.arch == "x86" and 1 or 0) + 1
local ARCH_SUFFIX = ({"osx64","osx","linux64","linux","win64","win32"}) [SUFFIX_IDX]
local BIN_PATH = string.format("lua/bin/gmsv_lua_preprocessor_%s.dll", ARCH_SUFFIX)

if file.Exists(BIN_PATH, "GAME") then
	require("lua_preprocessor")
else
	error("binary module \'" .. BIN_PATH .. "\' not found! anti_dump won't work without it!")
end

local parser = include("lua_parser.lua")

local type = _G.type
local ipairs = _G.ipairs

local file_exists = _G.file.Exists

local string_match = _G.string.match
local string_gsub = _G.string.gsub
local string_find = _G.string.find
local string_len = _G.string.len
local string_sub = _G.string.sub

local cs_lua_file = _G.AddCSLuaFile
local run_string = _G.RunString
local error_no_halt_with_stack = _G.ErrorNoHaltWithstack

local networked_file_paths = {}
local cs_lua_file_override = function(called_from_path, path)
	if type(path) ~= STRING_TYPE then
		networked_file_paths[string_gsub(called_from_path, LUA_VFS_PATTERN, EMPTY_STRING)] = true
		return
	end

	if file_exists(path, LUA_VFS) then
		networked_file_paths[path] = true
		return
	end

	local relative_path = (string_match(string_gsub(called_from_path, LUA_VFS_PATTERN, EMPTY_STRING), FILE_PATH_PATTERN) or EMPTY_STRING) .. FILE_PATH_SEPARATOR .. path
	if file_exists(relative_path, LUA_VFS) then
		networked_file_path[path] = true
	end
end

local ignore = false
local function run_server_code(path, code)
	-- original code to be ran on the server but doesnt add the client code
	ignore = true
	_G.AddCSLuaFile = function(file_to_add_path)
		return cs_lua_file_override(path, file_to_add_path)
	end

	local err_string = run_string(code, path, false)

	_G.AddCSLuaFile = cs_lua_file
	ignore = false

	if err_string then
		error_no_halt_with_stack(err_string)
	end
end

local last_block_data
local function get_server_blocks(ast, blocks)
	blocks = blocks or {}

	for i, statement in ipairs(ast.statements) do
		if not last_block_data.EndLine then
			last_block_data.EndLine = statement.line - 1
			last_block_data.EndIndex = statement.position - 1
		end

		if statement.type == "if" then
			if statement.condition.name == "SERVER" then
				local next_statement = ast.statements[i + 1]

				local block_data = next_statement and {
					StartLine = statement.line,
					EndLine = next_statement.line - 1,
					StartIndex = statement.position,
					EndIndex = next_statement.position - 1

				} or {
					StartLine = statement.line,
					StartIndex = statement.position,
				}

				last_block_data = block_data
				table.insert(blocks, block_data)
			else
				if statement.bodyTrue then
					get_server_blocks(statement.bodyTrue, blocks)
				end

				if statement.bodyFalse then
					get_server_blocks(statement.bodyTrue, blocks)
				end
			end
		elseif statement.type == "function" and statement.body then
			get_server_blocks(statement.body, blocks)
		end
	end

	return blocks
end

local function process_shared_code(code)
	local ast = parser.parse(parser.tokenize(code))
	local blocks = get_server_blocks(ast)
	last_block_data = nil

	for _, block in ipairs(blocks) do
		code = string_sub(code, 1, block.StartIndex - 1) .. string_gsub(string_sub(code, block.StartIndex, block.EndIndex), ONLY_NEWLINES_PATTERN, EMPTY_STRING) .. string_sub(code, block.EndIndex + 1)
	end

	return code
end

hook.Add("LuaPreProcess", "anti_dumping", function(path, code)
	if ignore then return end

	-- this shouldnt happen but just in case something fucky happens
	if string_match(path, LUA_VFS_CLIENT_AUTORUN_PATTERN) then return false end

	run_server_code(path, code)

	path = string_gsub(path, LUA_VFS_PATTERN, EMPTY_STRING)
	if not networked_file_paths[path] then return false end

	-- remove all the serverside code from the original code
	return process_shared_code(code)
end)

