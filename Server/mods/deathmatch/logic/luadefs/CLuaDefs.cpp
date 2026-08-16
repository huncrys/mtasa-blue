/*****************************************************************************
 *
 *  PROJECT:     Multi Theft Auto v1.0
 *  LICENSE:     See LICENSE in the top level directory
 *  FILE:        mods/deathmatch/logic/luadefs/CLuaDefs.cpp
 *  PURPOSE:     Lua definitions base class
 *
 *  Multi Theft Auto is available from https://www.multitheftauto.com/
 *
 *****************************************************************************/

#include "StdInc.h"
#include "CLuaDefs.h"
#include "CLuaClassDefs.h"
#include "lua/LuaCommon.h"
#include "CMapManager.h"
#include "CDebugHookManager.h"
#include "CPerfStatModule.h"
#include "CGame.h"

extern uint g_uiNetSentByteCounter;

namespace
{
    // For timing C function calls from Lua
    struct STimingFunction
    {
        STimingFunction(lua_State* luaVM, lua_CFunction f, TIMEUS startTime, uint uiStartByteCount)
            : luaVM(luaVM), f(f), startTime(startTime), uiStartByteCount(uiStartByteCount)
        {
        }
        lua_State*    luaVM;
        lua_CFunction f;
        TIMEUS        startTime;
        uint          uiStartByteCount;
    };
    std::list<STimingFunction> ms_TimingFunctionStack;
    bool                       ms_bRegisterdPostCallHook = false;
}  // namespace

CElementDeleter*           CLuaDefs::m_pElementDeleter = NULL;
CBlipManager*              CLuaDefs::m_pBlipManager = NULL;
CHandlingManager*          CLuaDefs::m_pHandlingManager = NULL;
CLuaManager*               CLuaDefs::m_pLuaManager = NULL;
CMarkerManager*            CLuaDefs::m_pMarkerManager = NULL;
CObjectManager*            CLuaDefs::m_pObjectManager = NULL;
CBuildingManager*          CLuaDefs::m_pBuildingManager = nullptr;
CPickupManager*            CLuaDefs::m_pPickupManager = NULL;
CPlayerManager*            CLuaDefs::m_pPlayerManager = NULL;
CRadarAreaManager*         CLuaDefs::m_pRadarAreaManager = NULL;
CRegisteredCommands*       CLuaDefs::m_pRegisteredCommands;
CElement*                  CLuaDefs::m_pRootElement = NULL;
CScriptDebugging*          CLuaDefs::m_pScriptDebugging = NULL;
CVehicleManager*           CLuaDefs::m_pVehicleManager = NULL;
CTeamManager*              CLuaDefs::m_pTeamManager = NULL;
CAccountManager*           CLuaDefs::m_pAccountManager = NULL;
CColManager*               CLuaDefs::m_pColManager = NULL;
CResourceManager*          CLuaDefs::m_pResourceManager = NULL;
CAccessControlListManager* CLuaDefs::m_pACLManager = NULL;
CMainConfig*               CLuaDefs::m_pMainConfig = NULL;

void CLuaDefs::Initialize(CGame* pGame)
{
    m_pRootElement = pGame->GetMapManager()->GetRootElement();
    m_pElementDeleter = pGame->GetElementDeleter();
    m_pBlipManager = pGame->GetBlipManager();
    m_pHandlingManager = pGame->GetHandlingManager();
    m_pLuaManager = pGame->GetLuaManager();
    m_pMarkerManager = pGame->GetMarkerManager();
    m_pObjectManager = pGame->GetObjectManager();
    m_pBuildingManager = pGame->GetBuildingManager();
    m_pPickupManager = pGame->GetPickupManager();
    m_pPlayerManager = pGame->GetPlayerManager();
    m_pRadarAreaManager = pGame->GetRadarAreaManager();
    m_pRegisteredCommands = pGame->GetRegisteredCommands();
    m_pScriptDebugging = pGame->GetScriptDebugging();
    m_pVehicleManager = pGame->GetVehicleManager();
    m_pTeamManager = pGame->GetTeamManager();
    m_pAccountManager = pGame->GetAccountManager();
    m_pColManager = pGame->GetColManager();
    m_pResourceManager = pGame->GetResourceManager();
    m_pACLManager = pGame->GetACLManager();
    m_pMainConfig = pGame->GetConfig();
    m_pLuaModuleManager = m_pLuaManager->GetLuaModuleManager();
}

bool CLuaDefs::CanUseFunction(const char* szFunction, lua_State* luaVM, bool bRestricted)
{
    // Get the belonging resource of the lua state
    CResource* pResource = m_pResourceManager->GetResourceFromLuaState(luaVM);
    if (pResource)
    {
        // Can we use the function? Return true so LUA can execute it
        if (m_pACLManager->CanObjectUseRight(pResource->GetName().c_str(), CAccessControlListGroupObject::OBJECT_TYPE_RESOURCE, szFunction,
                                             CAccessControlListRight::RIGHT_TYPE_FUNCTION, !bRestricted))
        {
            return true;
        }
        else
        {
            // Otherwise just return false
            m_pScriptDebugging->LogBadAccess(luaVM);
            return false;
        }
    }

    // Heh this should never happen
    return true;
}

//
// True for functions the rights check must never apply to.
//
// These are for OOP and establish the function to call, at which point the function is called normally so we get this called like so:
// Call 1: f = CLuaClassDefs::NewIndex
// Call 2: f = setElementHealth
// ignore new index as it isn't registered as an LuaCFunction and just throws an assert in debug/causes issues.
//
bool CLuaDefs::IsRightsCheckExempt(lua_CFunction f)
{
    // Quick cull of unknown pointer range
    if (CLuaCFunctions::IsNotFunction(f))
        return true;

    return f == (lua_CFunction)&CLuaClassDefs::NewIndex || f == (lua_CFunction)&CLuaClassDefs::StaticNewIndex || f == (lua_CFunction)&CLuaClassDefs::Index ||
           f == (lua_CFunction)&CLuaClassDefs::Call || f == (lua_CFunction)&CLuaClassDefs::ToString || f == (lua_CFunction)&CLuaClassDefs::ReadOnly ||
           f == (lua_CFunction)&CLuaClassDefs::WriteOnly;
}

int CLuaDefs::CanUseFunction(lua_CFunction f, lua_State* luaVM)
{
    if (IsRightsCheckExempt(f))
        return true;

    // Get associated resource. Resolving it from the VM costs a registry lookup on
    // LuaJIT, so the trampoline passes a cached one to CheckFunctionRights instead.
    return CheckFunctionRights(f, luaVM, lua_getownerresource(luaVM));
}

int CLuaDefs::CheckFunctionRights(lua_CFunction f, lua_State* luaVM, CResource& resource)
{
    // Since this method is used as a pre-call hook, make sure the resource is valid/running
    if (!resource.IsActive())
        return false;

    // Update execution time check. Take the VM from the state rather than from the
    // resource: CResource::m_pVM is only assigned once CreateVirtualMachine returns, so
    // it is still null for anything called while CLuaMain::Initialize runs, whereas the
    // owner stored at lua_open time is valid for the whole life of the VM.
    lua_getownercluamain(luaVM).CheckExecutionTime();

    // Check function right cache in resource
    bool bAllowed;

    // Check cached ACL rights
    if (resource.CheckFunctionRightCache(f, &bAllowed))
    {
        // If in cache, and not allowed, do warning here
        if (!bAllowed)
            m_pScriptDebugging->LogBadAccess(luaVM);
    }
    // Not cached yet
    else
    {
        // If not in cache, do full check
        bAllowed = true;

        // Grab the function name we're calling. If it's one of our functions, see if we can use it.
        CLuaCFunction* pFunction = CLuaCFunctions::GetFunction(f);

        // works for anything registered for Lua VM
        // e.g. setElementHealth, setElementFrozen
        if (pFunction)
        {
            // If it's not one of lua's functions, see if we allow it
            bAllowed = CLuaDefs::CanUseFunction(pFunction->GetName().c_str(), luaVM, pFunction->IsRestricted());
        }
        // works for custom ACL functions e.g.
        // Element.position and other custom oop definitions not registered by string.
        else
        {
            // get the 2nd upvalue (ACL Name)
            const char* szName = lua_tostring(luaVM, lua_upvalueindex(2));

            // if it has no name do nothing
            if (szName != NULL && strcmp(szName, "") != 0)
            {
                // get the function by name
                CLuaCFunction* pFunction = CLuaCFunctions::GetFunction(szName);
                if (pFunction)
                {
                    // check the resource cache for the Lua name we looked up
                    bAllowed = CLuaDefs::CanUseFunction(szName, luaVM, pFunction->IsRestricted());
                }
            }
        }
        // Update cache in resource
        resource.UpdateFunctionRightCache(f, bAllowed);
    }

    if (!g_pGame->GetDebugHookManager()->OnPreFunction(f, luaVM, bAllowed))
        return false;

    // If not allowed, do no more
    if (!bAllowed)
        return false;

    // Check if function timing is active
    if (g_pStats->bFunctionTimingActive || g_pGame->GetDebugHookManager()->HasPostFunctionHooks())
    {
        // Check if hook needs applying
        if (!ms_bRegisterdPostCallHook)
        {
            OutputDebugLine("[Lua] Registering PostCallHook");
            ms_bRegisterdPostCallHook = true;
#ifndef MTA_FORK_LUAJIT
            lua_registerPostCallHook(CLuaDefs::DidUseFunction);
#endif
        }
        // Start to time the function
        ms_TimingFunctionStack.push_back(STimingFunction(luaVM, f, GetTimeUs(), g_uiNetSentByteCounter));
    }
    return true;
}

#ifdef MTA_FUNCTION_ACL_WRAPPER
//
// Stands in for the VM's pre/post call hooks on LuaJIT.
//
// LuaJIT has no luaD_precall hook, but it does have LUAJIT_MODE_WRAPCFUNC: with it
// enabled the VM calls G(L)->wrapf(L, f) instead of f(L), straight from the VM
// assembly (see BC_FUNCCW in vm_*.dasc). That is the same shape as the patched Lua
// 5.1 pre-call hook, so no wrapper closure or upvalue juggling is needed.
//
// Only bc_cfunc_ext is switched, which covers externally registered C closures -
// LuaJIT's own built-ins keep using bc_cfunc_int and are never routed through here.
//
int CLuaDefs::CallWithACLCheck(lua_State* luaVM, lua_CFunction f)
{
    if (!CanUseFunction(f, luaVM))
        return 0;

    int iResults = f(luaVM);

    // CanUseFunction pushes onto the timing stack when timing is active and relies on
    // the post call hook to pop it again, so it has to be driven from here too.
    if (ms_bRegisterdPostCallHook)
        DidUseFunction(f, luaVM);

    return iResults;
}
#endif

//
// Called after a Lua function if post call hook has been installed
//
void CLuaDefs::DidUseFunction(lua_CFunction f, lua_State* luaVM)
{
    // Quick cull of unknown pointer range - Deals with calls from client dll (when the server has been loaded into the same process)
    if (CLuaCFunctions::IsNotFunction(f))
        return;

    if (!ms_TimingFunctionStack.empty())
    {
        // Check if the function used was being timed
        const STimingFunction& info = ms_TimingFunctionStack.back();
        if (info.f == f)
        {
            // Finish the timing
            TIMEUS elapsedTime = GetTimeUs() - info.startTime;
            uint   uiDeltaBytes = g_uiNetSentByteCounter - info.uiStartByteCount;
            // Record timing over a threshold
            if (elapsedTime >= CPerfStatFunctionTiming::ms_PeakUsThresh || uiDeltaBytes > 1000)
            {
                CLuaCFunction* pFunction = CLuaCFunctions::GetFunction(info.f);
                if (pFunction)
                {
                    CResource* pResource = g_pGame->GetResourceManager()->GetResourceFromLuaState(info.luaVM);
                    SString    strResourceName = pResource ? pResource->GetName() : SStringX("unknown");
                    CPerfStatFunctionTiming::GetSingleton()->UpdateTiming(strResourceName, pFunction->GetName().c_str(), elapsedTime, uiDeltaBytes);
                }
            }

            ms_TimingFunctionStack.pop_back();
        }
    }

    // Check if we should remove the hook
    if (!g_pStats->bFunctionTimingActive && !g_pGame->GetDebugHookManager()->HasPostFunctionHooks())
    {
        ms_TimingFunctionStack.clear();
        OutputDebugLine("[Lua] Removing PostCallHook");
        assert(ms_bRegisterdPostCallHook);
        ms_bRegisterdPostCallHook = false;
#ifndef MTA_FORK_LUAJIT
        lua_registerPostCallHook(NULL);
#endif
    }

    g_pGame->GetDebugHookManager()->OnPostFunction(f, luaVM);
}

//
// Prints a warning message in script-debug if the element is a player and not joined yet
//
void CLuaDefs::LogWarningIfPlayerHasNotJoinedYet(lua_State* luaVM, CElement* pElement)
{
    static auto szWarningText = "Modifying players before onPlayerJoin can cause desynchronization";

    if (pElement && IS_PLAYER(pElement))
    {
        auto pPlayer = static_cast<CPlayer*>(pElement);

        if (!pPlayer->IsJoined())
            m_pScriptDebugging->LogWarning(luaVM, "%s: %s", lua_tostring(luaVM, lua_upvalueindex(1)), szWarningText);
    }
}
