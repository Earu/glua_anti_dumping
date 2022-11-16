#include "GarrysMod/Lua/Interface.h"
#include <Platform.hpp>
#include "VTable.h"

#define RUNSTRINGEX 111

#ifndef _WIN32
#define __cdecl
#define __thiscall
#define __fastcall
#endif

VTable* stateHooker;
lua_State* luaState;

using namespace GarrysMod;

typedef void* (__thiscall* hRunStringExFn)(void*, char const*, char const*, char const*, bool, bool, bool, bool);
#if ARCHITECTURE_IS_X86_64
void* __fastcall hRunStringEx(void* _this, const char* fileName, const char* path, const char* str, bool bRun, bool bPrintErrors, bool bDontPushErrors, bool bNoReturns)
#else
void* __fastcall hRunStringEx(void* _this, void* unknown, const char* fileName, const char* path, const char* str, bool bRun, bool bPrintErrors, bool bDontPushErrors, bool bNoReturns)
#endif
{
	GarrysMod::Lua::ILuaBase* LUA = luaState->luabase;

	LUA->PushSpecial(Lua::SPECIAL_GLOB);
	LUA->GetField(-1, "hook");
	LUA->GetField(-1, "Run");
	LUA->PushString("LuaPreProcess");
	LUA->PushString(fileName);
	LUA->PushString(str);
	LUA->Call(3, 1);

	int type = LUA->GetType(-1);
	switch (type) {
		case (int)GarrysMod::Lua::Type::String:
		{
			str = LUA->GetString(-1);
			LUA->Pop(1);
		}
			break;
		case (int)GarrysMod::Lua::Type::Bool:
		{
			bool ret = LUA->GetBool(-1);
			LUA->Pop(1);

			if (ret == false) {
				LUA->Pop(2);
				return 0;
			}
		}
			break;
		default:
			LUA->Pop(1);
	}

	LUA->Pop(2);

	return hRunStringExFn(stateHooker->getold(RUNSTRINGEX))(_this, fileName, path, str, bRun, bPrintErrors, bDontPushErrors, bNoReturns);
}

class CLuaInterface
{
private:
	template<typename T>
	inline T get(unsigned short which)
	{
		return T((*(char ***)(this))[which]);
	}

public:
	void RunStringEx(const char* fileName, const char* path, const char* str, bool run = true, bool showErrors = true, bool pushErrors = true, bool noReturns = true)
	{
		return get<void(__thiscall*)(void*, char const*, char const*, char const*, bool, bool, bool, bool)>(RUNSTRINGEX)(this, fileName, path, str, run, showErrors, pushErrors, noReturns);
	}
};

GMOD_MODULE_OPEN()
{
	luaState = LUA->GetState();
	stateHooker = new VTable(luaState);
	stateHooker->hook(RUNSTRINGEX, (void*)&hRunStringEx);

	return 0;
}