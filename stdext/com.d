// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module stdext.com;

import std.utf;
import std.string;
import std.c.string;

import core.memory;

import sdk.port.base;
import sdk.port.stdole2;

import sdk.win32.oleauto;
import sdk.win32.objbase;

///////////////////////////////////////////////////////////////////////////////

extern(C) void* gc_malloc(size_t sz, uint ba = 0); 

class ComObject : IUnknown
{
	new(uint size)
	{
		void* p = gc_malloc(size, 1); // BlkAttr.FINALIZE
		return p;
	}

extern (System):
	override HRESULT QueryInterface(in IID* riid, void** ppv)
	{
		if (*riid == IID_IUnknown)
		{
			*ppv = cast(void*)cast(IUnknown)this;
			AddRef();
			return S_OK;
		}
		*ppv = null;
		return E_NOINTERFACE;
	}

	override ULONG AddRef()
	{
		LONG lRef = InterlockedIncrement(&count);
		if(lRef == 1)
		{
			void* vthis = cast(void*) this;
			GC.addRoot(vthis);
		}
		return lRef;
	}

	override ULONG Release()
	{
		LONG lRef = InterlockedDecrement(&count);
		if (lRef == 0)
		{
			void* vthis = cast(void*) this;
			GC.removeRoot(vthis);
			return 0;
		}
		return cast(ULONG)lRef;
	}

	LONG count = 0;		// object reference count
}

struct ComPtr(Interface)
{
	Interface ptr;

	this(Interface i = null, bool doref = true)
	{
		ptr = i;
		if(ptr && doref)
			ptr.AddRef();
	}

	this(IUnknown i)
	{
		ptr = qi_cast!(Interface)(i);
	}

	~this()
	{
		if(ptr)
			ptr.Release();
	}

	Interface detach()
	{
		Interface p = ptr;
		ptr = null;
		return p;
	}

	void opAssign(Interface i) 
	{
		if(ptr)
			ptr.Release();
		ptr = i;
		if(ptr)
			ptr.AddRef();
	}

	void opAssign(IUnknown i) 
	{ 
		if(ptr)
			ptr.Release();
		ptr = qi_cast!(Interface)(i);
	}

	Interface opCast(T:Interface)() { return ptr; }
	Interface* opCast(T:Interface*)() { return &ptr; }
	bool opCast(T:bool)() { return ptr !is null; }

	alias ptr this;
}

///////////////////////////////////////////////////////////////////////
bool queryInterface2(I)(I obj, in IID iid, in IID* riid, void** pvObject)
{
	if(*riid == iid)
	{
		*pvObject = cast(void*)obj;
		obj.AddRef();
		return true;
	}
	return false;
}

bool queryInterface(I)(I obj, in IID* riid, void** pvObject)
{
	return queryInterface2!(I)(obj, I.iid, riid, pvObject);
}

I qi_cast(I)(IUnknown obj)
{
	I iobj;
	if(obj && obj.QueryInterface(&I.iid, cast(void**)&iobj) == S_OK)
		return iobj;
	return null;
}

///////////////////////////////////////////////////////////////////////////////

T addref(T)(T p)
{
	if(p)
		p.AddRef();
	return p;
}

T release(T)(T p)
{
	if(p)
		p.Release();
	return null;
}

///////////////////////////////////////////////////////////////////////////////

static const size_t clsidLen  = 127;
static const size_t clsidSize = clsidLen + 1;

wstring GUID2wstring(in GUID clsid)
{
	//get clsid's as string
	wchar oleCLSID_arr[clsidLen+1];
	if (StringFromGUID2(*cast(GUID*)&clsid, oleCLSID_arr.ptr, clsidLen) == 0)
		return "";
	wstring oleCLSID = to_wstring(oleCLSID_arr.ptr);
	return oleCLSID;
}

string GUID2string(in GUID clsid)
{
	return toUTF8(GUID2wstring(clsid));
}

BSTR allocwBSTR(wstring s)
{
	return SysAllocStringLen(s.ptr, s.length);
}

BSTR allocBSTR(string s)
{
	wstring ws = toUTF16(s);
	return SysAllocStringLen(ws.ptr, ws.length);
}

wstring wdetachBSTR(ref BSTR bstr)
{
	if(!bstr)
		return ""w;
	wstring ws = to_wstring(bstr);
	SysFreeString(bstr);
	bstr = null;
	return ws;
}

string detachBSTR(ref BSTR bstr)
{
	if(!bstr)
		return "";
	wstring ws = to_wstring(bstr);
	SysFreeString(bstr);
	bstr = null;
	string s = toUTF8(ws);
	return s;
}

void freeBSTR(BSTR bstr)
{
	if(bstr)
		SysFreeString(bstr);
}

wchar* wstring2OLESTR(wstring s)
{
	int sz = (s.length + 1) * 2;
	wchar* p = cast(wchar*) CoTaskMemAlloc(sz);
	p[0 .. s.length] = s[0 .. $];
	p[s.length] = 0;
	return p;
}

wchar* string2OLESTR(string s)
{
	wstring ws = toUTF16(s);
	int sz = (ws.length + 1) * 2;
	wchar* p = cast(wchar*) CoTaskMemAlloc(sz);
	p[0 .. ws.length] = ws[0 .. $];
	p[ws.length] = 0;
	return p;
}

string detachOLESTR(wchar* oleStr)
{
	if(!oleStr)
		return null;

	string s = to_string(oleStr);
	CoTaskMemFree(oleStr);
	return s;
}

unittest
{
	// chinese for utf-8
	string str2 = "\xe8\xbf\x99\xe6\x98\xaf\xe4\xb8\xad\xe6\x96\x87";
	wchar* olestr2 = string2OLESTR(str2);
	string cmpstr2 = detachOLESTR(olestr2);
	assert(str2 == cmpstr2);

	// chinese for Ansi
	wstring str1 = "\ud5e2\ucac7\ud6d0\ucec4"w;
	wchar* olestr1 = wstring2OLESTR(str1);
	string cmpstr1 = detachOLESTR(olestr1);
	wstring wcmpstr1 = toUTF16(cmpstr1);
	assert(str1 == wcmpstr1);
}

wchar* _toUTF16z(string s)
{
	// const for D2
	return cast(wchar*)toUTF16z(s);
}

wchar* _toUTF16zw(wstring s)
{
	// const for D2
	wstring sz = s ~ "\0"w;
	return cast(wchar*)sz.ptr;
}

string to_string(in wchar* pText, int iLength)
{
	if(!pText)
		return "";
	string text = toUTF8(pText[0 .. iLength]);
	return text;
}

string to_string(in wchar* pText)
{
	if(!pText)
		return "";
	int len = wcslen(pText);
	return to_string(pText, len);
}

wstring to_wstring(in wchar* pText, int iLength)
{
	if(!pText)
		return ""w;
	wstring text = pText[0 .. iLength].idup;
	return text;
}

wstring to_cwstring(in wchar* pText, int iLength)
{
	if(!pText)
		return ""w;
	wstring text = pText[0 .. iLength].idup;
	return text;
}

wstring to_wstring(in wchar* pText)
{
	if(!pText)
		return ""w;
	int len = wcslen(pText);
	return to_wstring(pText, len);
}

wstring to_cwstring(in wchar* pText)
{
	if(!pText)
		return ""w;
	int len = wcslen(pText);
	return to_cwstring(pText, len);
}

wstring to_wstring(in char* pText)
{
	if(!pText)
		return ""w;
	int len = strlen(pText);
	return toUTF16(pText[0 .. len]);
}

///////////////////////////////////////////////////////////////////////
struct ScopedBSTR
{
	BSTR bstr;
	alias bstr this;

	this(string s)
	{
		bstr = allocBSTR(s);
	}
	this(wstring s)
	{
		bstr = allocwBSTR(s);
	}

	~this()
	{
		if(bstr)
		{
			freeBSTR(bstr);
			bstr = null;
		}
	}

	wstring wdetach()
	{
		return wdetachBSTR(bstr);
	}
	string detach()
	{
		return detachBSTR(bstr);
	}
}
