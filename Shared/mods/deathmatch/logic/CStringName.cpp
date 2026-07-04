/*****************************************************************************
 *
 *  PROJECT:     Multi Theft Auto
 *  LICENSE:     See LICENSE in the top level directory
 *  FILE:        CStringName.cpp
 *
 *  Multi Theft Auto is available from https://multitheftauto.com/
 *
 *****************************************************************************/
#include "StdInc.h"
#include "CStringName.h"

#include <array>
#include <string_view>

// Self-contained string hash, independent of the Lua/LuaJIT string representation.
// LuaJIT's own internal string hash is per-VM seeded (hash-flood protection) and can even be
// rehashed in place for a given string object during its lifetime, so it must not be read or
// relied upon here - this table needs one hash value that stays stable for the process lifetime.
// Algorithm is PUC-Lua 5.1's original luaS_hash, but in C++17
static StringNameHash MakeStringNameHash(const std::string_view& str)
{
    if (str.empty())
        return 0;

    const size_t len = str.length();
    const size_t step = (len >> 5) + 1; // if string is too long, don't hash all its chars

    auto h = static_cast<unsigned int>(str.length()); // seed
    for (size_t l1 = len; l1 >= step; l1 -= step) // compute hash
        h ^= (h << 5) + (h >> 2) + static_cast<unsigned char>(str[l1 - 1]);

    return h;
}

/*
    CStringNameStorage
*/
class CStringNameStorage
{
public:
    CStringNameData* Get(const std::string_view& str)
    {
        if (str.empty())
        {
            ZERO_NAME_DATA.AddRef();
            return &ZERO_NAME_DATA;
        }

        const StringNameHash                         hash = MakeStringNameHash(str);
        const uint32_t                               idx = hash & CStringName::STRING_TABLE_MASK;
        CIntrusiveDoubleLinkedList<CStringNameData>& list = m_table[idx];

        CStringNameData* data = list.First();
        while (data)
        {
            if (data->m_hash == hash && data->m_name == str)
                break;

            data = list.Next(data);
        }

        if (!data || data->m_refs == 0)
        {
            data = new CStringNameData(str, hash);
            list.InsertFront(data);
        }

        data->AddRef();

        return data;
    }

    void Release(CStringNameData* data)
    {
        const uint32_t idx = data->m_hash & CStringName::STRING_TABLE_MASK;

        if (data->m_refs == 0)
            m_table[idx].Erase(data);
    }

    CStringNameData* Find(const std::string_view& str, StringNameHash hash)
    {
        const uint32_t                               idx = hash & CStringName::STRING_TABLE_MASK;
        CIntrusiveDoubleLinkedList<CStringNameData>& list = m_table[idx];

        for (CStringNameData& data : list)
        {
            if (data.m_hash == hash && data.m_name == str)
                return &data;
        }

        return nullptr;
    }

    static CStringNameStorage& Instance()
    {
        static CStringNameStorage storage{};
        return storage;
    }

    static CStringNameData ZERO_NAME_DATA;

private:
    std::array<CIntrusiveDoubleLinkedList<CStringNameData>, CStringName::STRING_TABLE_LEN> m_table;
};

CStringNameData CStringNameStorage::ZERO_NAME_DATA{{}, 0u, 1};

/*
    CStringNameData
*/
void CStringNameData::AddRef()
{
    ++m_refs;
}

void CStringNameData::RemoveRef()
{
    if (m_hash == 0u)
        return;

    if (--m_refs == 0)
        CStringNameStorage::Instance().Release(this);
}

/*
    CStringName
*/
const CStringName CStringName::ZERO{};

CStringName::CStringName() : m_data(CStringNameStorage::Instance().Get({}))
{
}

CStringName::CStringName(const char* str) : m_data(CStringNameStorage::Instance().Get(str))
{
}

CStringName::CStringName(const std::string& str) : m_data(CStringNameStorage::Instance().Get(str))
{
}

CStringName::CStringName(const std::string_view& str) : m_data(CStringNameStorage::Instance().Get(str))
{
}

CStringName::CStringName(const CStringName& name) : m_data(name.m_data)
{
    if (m_data)
        m_data->AddRef();
}

CStringName::CStringName(CStringNameData* data) : m_data(data)
{
    if (m_data)
        m_data->AddRef();
}

CStringName& CStringName::operator=(const CStringName& name)
{
    if (m_data == name.m_data)
        return *this;

    m_data->RemoveRef();
    m_data = name.m_data;
    m_data->AddRef();

    return *this;
}

CStringName& CStringName::operator=(const std::string& str)
{
    *this = CStringName(str);
    return *this;
}

CStringName& CStringName::operator=(const std::string_view& str)
{
    *this = CStringName(str);
    return *this;
}

CStringName::~CStringName()
{
    if (m_data)
        m_data->RemoveRef();
}

void CStringName::Clear()
{
    *this = CStringName::ZERO;
}

CStringName CStringName::FromStringAndHash(const std::string_view& str, StringNameHash hash)
{
    if (CStringNameData* data = CStringNameStorage::Instance().Find(str, hash))
        return CStringName{data};

    // Create a new name
    return CStringName{str};
}
