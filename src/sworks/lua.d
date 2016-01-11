/** interface for Lua
 * Version:    0.0001(dmd2.096.2)
 * Date:       2016-Jan-11 21:19:27.44551
 * Authors:    KUMA
 * License:    CC0
 **/
/**
Description:
  これは Lua ($(LINK http://www.lua.org/)) へのラッパです。Lua 5.2に準拠していま
  す。
  porting として Derelict3 ($(LINK https://github.com/DerelictOrg/DerelictLua))
  を利用しています。
  Windows では実行時に lua52.dll を参照します。

Bugs:
  dmd2.069.2
    - userdataに確保された構造体のデストラクタが実行されない。


Error Handling:
  1. Lua のエラーハンドリング戦略である atpanic関数は終了後に abort関数を呼び
     出します。
  2. dmd2.067.0-b1 時点で、abort が呼ばれるとプログラムはクラッシュします。
  3. 1、 2 より LuaState class は atpanic 関数内で exit 関数を呼び出しています。
  4. 3 より、atpanic から D言語への処理の復帰は不可能です。
  5. 4 より、lua_pcall 系の関数を使うべき。
  6. 4 より、D言語から lua_error を呼ぶべきではない。
  7. Lua ライブラリは D言語の例外を処理できない。スタックトレースの情報もなくな
     ってしまう。
  8. 7 より、 6 の例外として、Lua から呼ばれているD言語の処理はデバグ情報を
     lua_error に渡すべき。
  9. 8 より、D言語の関数をラップする LuaState の機能は例外を受け取り、lua_error
     を呼び出します。
  10. 9 より、LuaState のユーザは D言語の例外を利用してください。
  11. 7 より、lua_CFunction 型の関数を使う(Lua から呼び出させる)場合、9 の
      LuaState の機能を利用できない為、その処理を自前で行う必要があります。

About this document:
  関数に関するドキュメント中の "Stack:" セクションは、その関数を実行した際の
  スタックの増減を示します。
  例えば、

  Stack:
      [-2, +3]

  とある場合は、スタック上から値が2個取り除かれた後、3個の値が新たに積まれること
  を意味します。
**/
module sworks.lua;

public import derelict.lua.lua;

import std.typecons : Typedef, Tuple;
import std.traits : isCallable, ReturnType;
debug import std.stdio : writeln, write;

//------------------------------------------------------------------------------
/// Lua へのインターフェイス
class LuaState
{
    /// ナカミ
    private lua_State* _l;

@trusted:

    /** luaL_newstate を呼び出し、パニック関数を登録する。
    登録されるパニック関数は exit() で終了する。

    Stack:
       [-0, +0]
    **/
    this()
    {
        DerelictLua.isLoaded || DerelictLua.load();
        _l = luaL_newstate();
        lua_atpanic(_l, &_atpanic);
    }
    /// 特に何もしない。
    @nogc pure nothrow
    this(lua_State* l) { _l = l; }

    /// 終了処理。必ずしも必要ではない。
    @nogc nothrow
    void clear(){ lua_close(_l); }

    ///
    @property @nogc pure nothrow
    auto ptr() inout { return _l; }

    /** Luaの標準ライブラリ読み込み。
    Stack:
        [-0, +0]
    **/
    @nogc nothrow
    LuaState openlibs() { luaL_openlibs(_l); return this; }

    /** 文字列を読み込んで、Luaの関数としてスタックに積む。実行はしない。
    Stack:
        [-0, +1]
    Throws:
        LuaException = 読み込みに失敗した場合に投げられる。
    **/
    LuaState loadBuffer(const(char)[] buf, const(char)* name = "anonymous",
                        string file = __FILE__, size_t line = __LINE__)
    {
        ensuccess(luaL_loadbuffer(_l, buf.ptr, buf.length, name), file, line);
        return this;
    }

    /** ファイルを読み込んで、関数としてスタックに積む。実行はしない。
    Stack:
        [-0, +1]
    Throws:
        LuaException = 読み込みに失敗した場合に投げられる。
    **/
    LuaState loadFile(const(char)* fn, string f = __FILE__, size_t l = __LINE__)
    {
        ensuccess(luaL_loadfile(_l, fn), f, l);
        return this;
    }

    /** ファイルを読み込んで実行する。
    Stack:
        [-0, +0]
    Throws:
        LuaException
    **/
    LuaState doFile(const(char)* fn, string f = __FILE__, size_t l = __LINE__)
    {
        ensuccess(luaL_dofile(_l, fn), f, l);
        return this;
    }

    /** 文字列をスクリプトとして実行する。
    Stack:
        [-0, +0]
    Throws:
        LuaException
    **/
    LuaState doString(const(char)* buf, string f = __FILE__,
                      size_t l = __LINE__)
    {
        ensuccess(luaL_dostring(_l, buf), f, l);
        return this;
    }

    /** スタック頂上に積まれた関数を実行する。
    Stack:
      [-1, 0]

    Throws:
        LuaException
    **/
    template pcall(Returns...)
    {
        auto pcall(Args...)(Args args)
        {
            auto i = stackTop;
            int numArgs = args.length;
            int numReturns = Returns.length;
            static if (Args.length==1 && is(Args[0]==OnStack))
                numArgs = cast(int)args[0];
            else
                push(args);

            static if (Returns.length==1 && is(typeof(Returns[0])==OnStack))
                numReturns = cast(int)Returns[0];

            ensuccess(lua_pcall(_l, numArgs, numReturns, 0));

            static if (Returns.length==1 && is(typeof(Returns[0])==OnStack))
                return numReturns;
            else
            {
                auto r = getAs!(Tuple!Returns)(i);
                pop(Returns.length);
                return r;
            }
        }
    }

    //--------------------------------------
    // about stack
    /** スタックにこれから積める余裕があるかどうか。
    Stack:
        [-0, +0]
    **/
    @nogc nothrow
    bool checkStack(int sz) { return lua_checkstack(_l, sz) != 0; }

    /** スタックのサイズを得る。
    Stack:
        [-0, +0]
    **/
    @property @nogc nothrow
    int stackTop() { return lua_gettop(_l); }

    /** スタックのサイズを設定する。
    Stack:
        [-?, +?]
    **/
    @property @nogc nothrow
    LuaState stackTop(int i) { lua_settop(_l, i); return this; }

    // 負数で与えられたスタック上の位置を整数に変換する。
    @nogc nothrow
    int abs(int i)
    { return (i < 0 && i != LUA_REGISTRYINDEX) ? i + stackTop + 1 : i; }

    /** スタック上の値をコピーし、スタックに積む
    Stack:
        [-0, +1]
    **/
    @nogc nothrow
    LuaState pushValue(int i) { lua_pushvalue(_l, i); return this; }

    /** スタックから値を削除
    Stack:
        [-1, +0]
    **/
    @nogc nothrow
    LuaState remove(int i) { lua_remove(_l, i); return this; }

    /** スタック頂上の値を i の位置に挿入。スタックの高さは変わらない。
    Stack:
        [-1, +1]
    **/
    @nogc nothrow
    LuaState insert(int i) { assert(0 < i); lua_insert(_l, i); return this; }

    /** スタック頂上の値を、i の位置に入れる。スタックの高さは1減る。
    Stack:
        [-1, +0]
    **/
    @nogc nothrow
    LuaState replace(int i) { lua_replace(_l, i); return this; }

    /** スタックに値を積む。
    Stack:
        [-0, +1]
    **/
    LuaState push(Args...)(Args args)
    {
        import std.traits : isPointer, isInstanceOf, fullyQualifiedName,
            isCallable;
        import std.typecons : isTuple;

        foreach (i, v; args)
        {
            alias T = Args[i];
            static if      (is(T == bool)) lua_pushboolean(_l, v);
            else static if (is(T : ptrdiff_t)) lua_pushinteger(_l, v);
            else static if (is(T : double)) lua_pushnumber(_l, v);
            else static if (is(T : const(char)[]))
                lua_pushlstring(_l, v.ptr, v.length);
            else static if (is(T : const(char)*)) lua_pushstring(_l, v);
            else static if (is(T : lua_CFunction)) lua_pushcclosure(_l, v, 0);
            else static if (is(T : U[], U))
            {
                lua_createtable(_l, cast(int)v.length, 0);
                auto table = stackTop;
                foreach (key, val; v)
                {
                    push(key+1); // Lua の配列は1開始
                    push(val);
                    lua_settable(_l, table);
                }
            }
            else static if (is(T : U[V], U, V))
            {
                lua_createtable(_l, 0, cast(int)v.length);
                auto table = stackTop;
                foreach (key, val; v)
                {
                    push(key);
                    push(val);
                    lua_settable(_l, table);
                }
            }
            else static if (isCallable!T)
            {
                auto d = newUserData!(DelContainer!T);
                d.payload = v;
                lua_pushcclosure(_l, &delWrapper!T, 1);
            }
            else static if (is(T == LuaRegRef))
                lua_rawgeti(_l, LUA_REGISTRYINDEX, cast(int)v);
            else static if (isTuple!T) foreach (one; v) push(one);
            else static if (isInstanceOf!(LuaTable, T))
            {
                enum int named = T.namedMembers.length;
                enum int unnamed = v.length - named;
                lua_createtable(_l, unnamed, named);
                int counter = 1;
                foreach (j, one; T.fieldNames)
                {
                    static if (0 < one.length)
                        setField(-1, one, __traits(getMember, v, one));
                    else setField(-1, counter++, v[j]);
                }
            }
            else static if (is(T U == class) ||
                            is(T : U*, U) && is(U == struct))
            {
                import std.traits : fullyQualifiedName;
                import std.utf : toUTFz;
                alias toUTF8z = toUTFz!(const(char)*);

                if (v is null) pushNil;
                else
                {
                    // メソッドへのアクセス
                    auto regs = memRegs!U;
                    luaL_newlibtable(_l, regs);
                    auto lib_id = stackTop;

                    push(cast(void*)v);
                    luaL_setfuncs(_l, regs.ptr, 1);

                    setField(lib_id, NAME_KEY, fullyQualifiedName!T);
                    setField(lib_id, INSTANCE_KEY, cast(void*)v);

                    // メンバ変数/GCへのアクセス
                    auto _meta = metaRegs!U;
                    luaL_newmetatable(_l, toUTF8z(fullyQualifiedName!T));
                    push(cast(void*)v);
                    luaL_setfuncs(_l, _meta.ptr, 1);

                    lua_setmetatable(_l, lib_id);
                }
            }
            else static if (is(T == struct))
            {
                enum named =
                {
                    int counter;
                    foreach (one; __traits(allMembers, T))
                        if (isMemberVariable!(T, one)) ++counter;
                    return counter;
                }();

                static if (0 < named)
                {
                    lua_createtable(_l, 0, named);
                    foreach (one; __traits(allMembers, T))
                        static if (isMemberVariable!(T, one))
                            setField(-1, one, __traits(getMember, v, one));
                }
                else
                {
                    import std.conv : to;
                    try push(v.to!string); catch (Throwable){}
                }
            }
            else static if (isPointer!T)
                lua_pushlightuserdata(_l, cast(void*)v);
            else static assert(0, T.stringof ~ " is not supported by push().");
        }
        return this;
    }

    /** Lua からそのまま呼び出し可能な関数、あるいは参照可能な値の登録。
    Stack:
        [-0, +0|1]
    **/
    LuaState push(alias T)()
        if (is(typeof(&T): lua_CFunction) || (!is(T) && !isCallable!T))
    {
        static if (is(typeof(&T) : lua_CFunction)) return push(&T);
        else return push(T);
    }


    /** Lua から呼び出し可能な関数を登録する。
    これで登録できる関数は、static で、alias が取れるもの。
    Params:
        name = Lua から参照させる関数の名前。
               null を渡すとLuaのグローバルスコープに登録されずスタック頂上に
               残る。
    Stack:
        [-0, +0|1]
    **/
    @nogc nothrow
    auto push(alias T)()
        if (__traits(isStaticFunction, T) && !is(typeof(&T) : lua_CFunction))
    { return push(&funcWrapper!T); }


    /** クラスの及び構造体の static/非static なメンバ関数を Lua から呼び出し
    可能な関数として登録する。

    戻り値として返されるメモリ領域は Lua により確保され、Lua の GC によって管理
    されている。
    D言語の GC に対する GC.addRange と GC.removeRange は自動で実行される。

    Stack:
        [-0, +1]
    **/
    auto push(alias T, A...)(A args) if (is(T == class) || is(T == struct))
    { return push(newUserData!T(args)).remove(-2); }

    /** enum をインストールする。
    Stack:
      [-0, +1]
     **/
    auto push(T)() if (is(T == enum))
    {
        extern(C) static @nogc nothrow
        int _newindex(lua_State* l)
        {
            lua_pushstring(l, ("enum type " ~ T.stringof ~
                                " in D. this couldn't be modified.\0").ptr);
            lua_error(l);
            return 0;
        }
        enum int Ecount = __traits(allMembers, T).length;

        lua_createtable(_l, 0, 0); // entity
        auto regs = [luaL_Reg("__newindex", &_newindex), luaL_Reg(null, null)];
        luaL_newlibtable(_l, regs); // metatable
        luaL_setfuncs(_l, regs.ptr, 0);
        push("__index");
        lua_createtable(_l, 0, Ecount); // __index metatable
        foreach (one; __traits(allMembers, T))
        {
            push(one, __traits(getMember, T, one));
            rawSet(-3);
        }
        rawSet(-3);
        lua_setmetatable(_l, -2);
        return this;
    }

    /** スタックに nil を積む。
    Stack:
        [+1, -0]
    **/
    @nogc nothrow
    LuaState pushNil() { lua_pushnil(_l); return this; }

    /** スタック頂上の値を取り除く。
    Stack:
        [-i, +0]
    **/
    @nogc nothrow
    LuaState pop(int i = 1) { lua_settop(_l, -i-1); return this; }

    /** スタック上の値の型情報
    Stack:
        [-0, +0]
    **/
    @nogc nothrow
    int type(int i) { return lua_type(_l, i); }

    /**
    Stack:
        [-0, +0]
    **/
    @nogc nothrow
    bool isType(int T)(int i) { return T == lua_type(_l, i); }

    // type の戻り値を文字列に変換する。
    static @nogc pure nothrow
    string typeName(int i)
    {
        switch(i)
        {
            case        LUA_TNIL: return "nil";
            break; case LUA_TNUMBER: return "number";
            break; case LUA_TBOOLEAN: return "boolean";
            break; case LUA_TSTRING: return "string";
            break; case LUA_TTABLE: return "table";
            break; case LUA_TFUNCTION: return "function";
            break; case LUA_TUSERDATA: return "userdata";
            break; case LUA_TTHREAD: return "thread";
            break; case LUA_TLIGHTUSERDATA: return "lightuserdata";
            break; default: return "unknown";
        }
        assert(0);
    }

    /** スタック上の値を型指定して取り出す。
    getAs!(const(char)[]) で Lua が確保した文字列を返します。
    その為、Lua に処理が戻った後の値は未定義です。
    Lua が確保した文字列は、Null終端が保証されています。
    getAs!string では idup されます。これも Null終端が保証されます。

    Stack:
        [-0, +0]

    Throws:
        Exception = 指定の型ではなかった場合
    **/
    T getAs(T)(int i){ return _getAs!(T, true)(i); }
    /// デフォルト値つき。
    T getAs(T)(int i, T def){ return _getAs!(T, false)(i, def); }

    ///
    T getUserDataAs(T)(int i) { return cast(T)_getAs!(void*, true)(i); }
    /// ditto
    T getUserDataAs(T)(int i, T def)
    { return cast(T)_getAs!(void*, false)(i, def); }

    ///
    @nogc nothrow
    auto getThread(int i) { return lua_tothread(_l, i); }

    /** スタック上の i の位置の値を文字列に直して取得する。debugにも。
    Stack:
        [-0, +0]
    **/
    string getStringAt(int i)
    {
        import std.string : join;
        import std.conv : to;
        import std.array : Appender;
        switch(type(i))
        {
        case LUA_TNIL: return "[NIL]";
        case LUA_TBOOLEAN: return getAs!bool(i) ? "[TRUE]" : "[FALSE]";
        case LUA_TNUMBER: return getAs!double(i).to!string;
        case LUA_TSTRING: return getAs!string(i);
        case LUA_TTABLE:
            Appender!(string[]) buf;
            buf.reserve(lua_rawlen(_l, i));
            i = abs(i);
            lua_pushnil(_l);
            while(0 != lua_next(_l, i))
            {
                buf.put([getStringAt(-2), ": ", getStringAt(-1)].join);
                lua_settop(_l, -2);
            }
            return ["[", buf.data.join(", "), "]"].join;
        case LUA_TFUNCTION: return "[FUNCTION]";
        case LUA_TUSERDATA: return "[USERDATA]";
        case LUA_TTHREAD: return "[THREAD]";
        case LUA_TLIGHTUSERDATA: return "[LIGHTUSERDATA]";
        default: return "[UNKNOWN]";
        }
        assert(0);
    }

    //--------------------------------------------------------------------------
    // about table
    /** グローバルスコープのテーブルにアクセスし、値をスタックに積む。
    Stack:
        [-0, +1]
    **/
    @nogc nothrow
    LuaState getGlobal(const(char)* name)
    { lua_getglobal(_l, name); return this; }

    /**
    Stack:
        [-1, +0]
    **/
    @nogc nothrow
    LuaState setGlobal(const(char)* name)
    { lua_setglobal(_l, name); return this; }

    /** スタック上の i の位置にあるテーブルから値を取り出す。
    Stack:
        [-0, +0]
    **/
    T getFieldAs(T, K)(int i, K key) { return _getFieldAs!(T, true)(i, key); }
    /// ditto
    T getFieldAs(T, K)(int i, K key, T def)
    {return _getFieldAs!(T, false)(i, key, def);}
    /// ditto
    T getFieldUserDataAs(T, K)(int i, K key)
    { return cast(T)_getFieldAs!(void*, true)(i, key); }
    /// ditto
    T getFieldUserDataAs(T, K)(int i, K key, T def)
    { return cast(T)_getFieldAs!(void*, false)(i, key, def); }

    private enum NAME_KEY = "_name_";
    private enum INSTANCE_KEY = "_instance_";

    /**
    Stack:
        [-0, +0]
    **/
    LuaState setField(T, K)(int i, K key, T val)
    {
        i = abs(i);
        push(key);
        push(val);
        lua_settable(_l, i);
        return this;
    }

    /**
    value はスタックの頂上に積まれているものとする。

    Stack:
        [-1, +0]
    **/
    LuaState setField(K)(int i, K key)
    {
        auto ptop = stackTop;
        i = abs(i);
        push(key);
        insert(ptop);
        lua_settable(_l, i);
        return this;
    }

    //--------------------------------------------------------------------------
    // about registry

    /** レジストリの値をスタックに積む。
    Stack:
        [-0, +1]
    **/
    @nogc
    LuaState getRegistry(K)(K key)
    { push(key); lua_gettable(_l, LUA_REGISTRYINDEX); return this; }

    /** レジストリから値を取り出す。
    Stack:
        [-0, +0]
    **/
    T getRegistryAs(T, K)(K key)
    { return _getFieldAs!(T, true)(LUA_REGISTRYINDEX, key); }

    /// ditto
    T getRegistryAs(T, K)(K key, T def)
    { return _getFieldAs!(T, false)(LUA_REGISTRYINDEX, key, def); }

    /**
    Stack:
        [-0, +0]
    **/
    @nogc nothrow
    LuaState setRegistry(T, K)(K key, T val)
    { setField(LUA_REGISTRYINDEX, key, val); return this; }

    /**
    value はスタックの頂上に積まれているものとする。
    Stack:
        [-1, +0]
    **/
    @nogc nothrow
    LuaState setRegistry(K)(K key)
    { setField(LUA_REGISTRYINDEX, key); return this; }

    /** スタック頂上にある値をレジストリへ保存し、値への key を返す。
    Stack:
        [-1, +0]
    **/
    @nogc nothrow
    LuaRegRef getRefRegistry()
    { return LuaRegRef(luaL_ref(_l, LUA_REGISTRYINDEX)); }

    /** レジストリから key に保存されている値を削除する。
    Stack:
        [-0, +0]
    **/
    @nogc nothrow
    LuaState unRefRegistry(LuaRegRef key)
    { luaL_unref(_l, LUA_REGISTRYINDEX, cast(int)key); return this; }


    //--------------------------------------------------------------------------
    // raw access
    /**
    Stack:
        [-0, +1]
    **/
    T rawGetAs(T)(int i, int n)
    {
        lua_rawgeti(_l, i, n);
        return _getAs!(T, true)(-1);
    }

    /** スタック上の位置 i にある配列/テーブルの table[n]を取り出してスタックに
    積む

    Stack:
        [-0, +1]
    **/
    @nogc nothrow
    LuaState rawGet(int i, int n) { lua_rawgeti(_l, i, n); return this; }

    /** キーは lightuserdata
    Stack:
        [-0, +1]
    **/
    @nogc nothrow
    LuaState rawGet(int i, const(void)* p)
    { lua_rawgetp(_l, i, p); return this; }

    /** スタック上の位置 i にある配列/テーブルの table[key] を取り出してスタック
    に積む
    key はスタックの頂上に積まれているものとする。

    Stack:
        [-1, +1]
    **/
    @nogc nothrow
    LuaState rawGet(int i) { lua_rawget(_l, i); return this; }


    /** スタック上の位置 i にある配列/テーブルの table[n] に値を設定する。
    設定される値は、スタックの頂上に積まれているものとする。
    Stack:
        [-1, +0]
    **/
    @nogc nothrow
    LuaState rawSet(int i, int n) { lua_rawseti(_l, i, n); return this; }

    /** キーは lightuserdata
    Stack:
        [-1, +0]
    **/
    @nogc nothrow
    LuaState rawSet(int i, const(void)* p)
    { lua_rawsetp(_l, i, p); return this; }

    /** キー → 値 = 頂上 の順にスタックに積まれているものとする。
    Stack:
        [-1, +0]
    **/
    @nogc nothrow
    LuaState rawSet(int i) { lua_rawset(_l, i); return this; }


    /** レジストリから key = n の値を取り出し、スタックに積む。
    Stack:
        [-0, +1]
    **/
    T rawGetRegistryAs(T)(LuaRegRef n)
    {
        lua_rawgeti(_l, LUA_REGISTRYINDEX, cast(int)n);
        return _getAs!(T, true)(-1);
    }

    /// ditto
    T rawGetRegistryAs(T)(const(void)* p)
    {
        lua_rawgetp(_l, LUA_REGISTRYINDEX, p);
        return _getAs!(T, true)(-1);
    }

    /** レジストリから key=n の値を取り出し、スタックに積む
    Stack:
        [-0, +1]
    **/
    @nogc nothrow
    LuaState rawGetRegistry(LuaRegRef n)
    { lua_rawgeti(_l, LUA_REGISTRYINDEX, cast(int)n); return this; }

    /** キーは lightuserdata
    Stack:
        [-0, +1]
    **/
    @nogc nothrow
    LuaState rawGetRegistry(const(void)* p)
    { lua_rawgetp(_l, LUA_REGISTRYINDEX, p); return this; }

    /** キーはスタックの頂上にある
    Stack:
        [-1, +1]
    **/
    @nogc nothrow
    LuaState rawGetRegistry()
    { lua_rawget(_l, LUA_REGISTRYINDEX); return this; }

    /** スタックの頂上に積まれている値をレジストリの key=n に設定する。
    Stack:
        [-1, +0]
    **/
    @nogc nothrow
    LuaState rawSetRegistry(LuaRegRef n)
    { lua_rawseti(_l, LUA_REGISTRYINDEX, cast(int)n); return this;}

    /** キーは lightuserdata
    Stack:
        [-1, +0]
    **/
    @nogc nothrow
    LuaState rawSetRegistry(const(void)* p)
    { lua_rawsetp(_l, LUA_REGISTRYINDEX, p); return this; }

    /** キーはスタックの頂上にある。
    Stack:
        [-2, +0]
    **/
    @nogc nothrow
    LuaState rawSetRegistry()
    { lua_rawset(_l, LUA_REGISTRYINDEX); return this; }

    //--------------------------------------------------------------------------
    // userdata
    /** ユーザーデータを作り、スタックに積む。

    ユーザーデータとして確保された領域は、GC.addRange される。
    つまり、メンバ変数に D言語側で new した値が格納されていても GC が検出
    できる。よね。
    また、__gc metamethod が付加される。LuaのGCによる回収時に デストラクタと
    GC.removeRange が呼ばれる。
    metamethod table は fullyQualifiedName でレジストリに登録される。

    Notice:
        この値をpopしてしまうとスコープアウトする為、注意。

    Stack:
        [-0, +1]
    **/
    nothrow
    auto newUserData(T, ARGS...)(ARGS args)
        if (is(T == class) || is(T == struct))
    {
        import std.conv : emplace;
        import core.memory: GC;
        static if      (is(T == class)) enum L = __traits(classInstanceSize, T);
        else static if (is(T == struct)) enum L = T.sizeof;
        auto t = lua_newuserdata(_l, L);
        GC.addRange(t, L);
        static if (__traits(hasMember, T, "__ctor") &&
                   0 < ParameterTypeTuple!(T.__ctor).length &&
                   is(ParameterTypeTuple!(T.__ctor)[0] : LuaState))
            return emplace!T(t[0..L], this, args);
        else return emplace!T(t[0..L], args);
    }

    /// GC.addRange されない生ポ
    @nogc nothrow
    void* newUserData(T: size_t)(T size) { return lua_newuserdata(_l, size); }

    //--------------------------------------
    // about calling a function in lua

    /// Lua の関数を呼び出す。戻り値は、std.typecons.Tuple。
    /// 戻り値が一つの場合でも Tuple でラップされた値が戻る。
    template callFunc(R...)
    {
        Tuple!R callFunc(ARGS...)(const(char)* f, ARGS args)
        {
            getGlobal(f);
            return pcall!R(args);
        }
    }

    /** Lua のグローバルスコープから関数名 name の関数を取り出し、
    Lua のレジストリに登録しする。戻り値のファンクタを呼び出すことで関数を実行
    できる。

    Stack:
        [-0, +0]
    **/
    auto getFunc(const(char)* name = null, R...)()
    { return FuncOfLua!(name, R)(this); }


    /** スタック上の全てを文字列にして返す。debug に。
    Stack:
        [-0, +0]
    **/
    string dumpStack()
    {
        import std.conv : to;
        import std.string : join;

        auto l = stackTop;
        auto buf = new string[l*4];
        buf[0] = "stack size : ";
        buf[1] = l.to!string;
        buf[2] = "\n";
        for (int i = 1 ; i <= l ; ++i)
        {
            buf[i*4] = i.to!string;
            buf[i*4+1] = " : ";
            buf[i*4+2] = getStringAt(i);
            buf[i*4+3] = "\n";
        }
        return buf.join;
    }

    // enforce みたいなん。 lua_pcall の戻り値を処理する。
    int ensuccess(int i, string file = __FILE__, size_t line = __LINE__)
    {
        string msg;
        final switch(i)
        {
            case LUA_OK: return i;
            case LUA_YIELD: return i;
            case LUA_ERRSYNTAX:
                msg = "syntax error : ";
                break;
            case LUA_ERRRUN:
                msg = "a runtime error : ";
                break;
            case LUA_ERRMEM:
                msg = "memory allocation error : ";
                break;
            case LUA_ERRERR:
                msg = "error in message handler : ";
                break;
            case LUA_ERRGCMM:
                msg = "error in gc : ";
        }
        throw new LuaException(_l, msg ~ getAs!string(-1), file, line);
        assert(0);
    }

//------------------------------------------------------------------------------
private:

    // getAs のナカミ
    T _getAs(T, bool STRICT)(int i, T def = T.init)
    {
        import std.conv : to;
        import std.traits : isPointer, isInstanceOf;
        import std.typecons : isTuple;

        assert(!STRICT || i <= stackTop, "need " ~ i.to!string ~
               " arguments, got " ~ stackTop.to!string ~ ".");

        void raise()
        {
            throw new LuaException(
                _l, "conversion error. (" ~ T.stringof ~ " expected, got " ~
                typeName(type(i)) ~ ")");
        }
        void checkType(int LT)() { if (LT != type(i)) raise; }

        static if      (is(T == bool)) return lua_toboolean(_l, i) != 0;
        else static if (is(T : ptrdiff_t))
        {
            int isnum;
            auto v = lua_tointegerx(_l, i, &isnum);
            if             (isnum) return cast(T)v;
            else static if (STRICT) raise;
            else return def;
        }
        else static if (is(T : real))
        {
            int isnum;
            auto v = lua_tonumberx(_l, i, &isnum);
            if             (isnum) return v;
            else static if (STRICT) raise;
            else return v;
        }
        else static if (is(T : const(char)[]))
        {
            size_t length;
            auto p = lua_tolstring(_l, i, &length);

            if             (p !is null){}
            else static if (STRICT) raise;
            else return def;

            static if (is(T == string))
                return p[0..length+1].idup[0..length];
            else
                return p[0..length];
        }
        else static if (is(T == lua_CFunction))
        {
            if             (auto v = lua_tocfunction(_l, i)) return v;
            else static if (STRICT) raise;
            else return def;
        }
        else static if (is(T : U[N], U, size_t N))
        {
            if             (isType!LUA_TTABLE(i)){}
            else static if (STRICT) raise;
            else return def;

            U[N] v;
            U d;
            for (size_t j = 0; j < N; ++j)
            {
                static if (!STRICT) d = def[j];
                v[j] = _getFieldAs!(U, STRICT)(i, j+1, d);
            }
            return v;
        }
        else static if (is(T : U[], U))
        {
            if             (isType!LUA_TTABLE(i)){}
            else static if (STRICT) raise;
            else return def;

            auto v = new U[lua_rawlen(_l, i)];
            for (size_t j = 0; j < v.length; ++j)
                v[j] = _getFieldAs!(U, STRICT)(i, j+1);
        }
        else static if (is(T : U[V], U, V))
        {
            if             (isType!LUA_TTABLE(i)){}
            else static if (STRICT) raise;
            else return def;

            T v;
            lua_pushnil(_l);
            while (0 != lua_next(_l, i))
            {
                v[_getAs!(V, STRICT)(-2)] = _getAs!(U, STRICT)(-1);
                lua_settop(_l, -2);
            }
            return v;
        }
        else static if (isTuple!T)
        {
            T r;
            foreach (int j, ref one; r)
                one = _getAs!(typeof(one), STRICT)(i+j, def[j]);
            return r;
        }
        else static if (is(T : Loosely!U, U))
            return T(_getAs!(U, false)(i));
        else static if (isInstanceOf!(LuaTable, T) ||
                        isInstanceOf!(LuaTableLoose, T))
        {
            if             (isType!LUA_TTABLE(i)){}
            else static if (STRICT) raise;
            else return def;

            enum S = isInstanceOf!(LuaTable, T) && STRICT;
            T r;
            int counter;
            foreach (j, key; T.fieldNames)
            {
                static if (0 < key.length)
                    __traits(getMember, r, key) =
                        _getFieldAs!(r.Types[j], S)(i, key, def[j]);
                else
                    __traits(getMember, r, key) =
                        _getFieldAs!(r.Types[j], S)(i, ++counter, def[j]);
            }
            return r;
        }
        else static if (is(T == struct))
        {
            if             (isType!LUA_TTABLE(i)){}
            else static if (STRICT) raise;
            else return def;

            T t;
            foreach (one; __traits(derivedMembers, T))
                static if (isMemberVariable!(T, one))
                    __traits(getMember, t, one) =
                        _getFieldAs!(
                            typeof(__traits(getMember, t, one)), STRICT)
                            (i, one, __traits(getMember, def, one));
            return t;
        }
        else static if (is(T == class) ||
                        is(T : U*, U) && is(U == struct))
        {
            if             (isType!LUA_TTABLE(i)){}
            else static if (STRICT) raise;
            else return def;
            return cast(T)_getFieldAs!(void*, STRICT)(i, INSTANCE_KEY);
        }
        else static if (isPointer!T)
        {
            auto p = lua_touserdata(_l, i);
            if             (p !is null) return cast(T)p;
            else static if (STRICT) raise;
            else return def;
        }
        else static assert(0, T.stringof ~ " is not supported by getAs");
        assert(0);
    }

    // getFieldAs のナカミ
    T _getFieldAs(T, bool STRICT, K)(int i, K key, T def = T.init)
    {
        i = abs(i);
        push(key);
        lua_gettable(_l, i);
        auto r = _getAs!(T, STRICT)(-1, def);
        lua_settop(_l, -2);
        return r;
    }

    //--------------------------------------------------------------------------
    // about a function called by lua

    /* lua_error を経由して panic 関数を呼び出す。
    Stack:
        [-0, +1]
    */
    nothrow
    void _error(Throwable t)
    {
        try push(t.toString);
        catch (Throwable){}
        lua_error(_l);
    }
}
// The end of LuaState
//##############################################################################
//##############################################################################

//------------------------------------------------------------------------------
/** コルーチンへのインターフェイス

このクラスから呼ばれるスクリプト内では、グローバルスコープに、
yield という関数が定義されている。
**/
class LuaThread : LuaState
{
    private int _result;

    @trusted:

    private extern(C) static @nogc
    int _yielder(lua_State* l) { return lua_yield(l, lua_gettop(l)); }

    //
    this()
    {
        super();
        push!_yielder.setGlobal("yield");
        _result = LUA_OK;
    }

    //
    @nogc nothrow
    this(lua_State* ls)
    {
        super(ls);
        push!_yielder.setGlobal("yield");
        _result = LUA_OK;
    }

    /// 前回の resume が yield で終わっているか。
    @property @nogc pure nothrow
    bool isRunning() const { return _result == LUA_YIELD; }

    /// スクリプトを開始/再開する。
    template resume(R...)
    {
        auto resume(Args...)(lua_State* from, Args args)
        {
            push(args);
            auto i = stackTop - args.length;
            _result = ensuccess(lua_resume(_l, from, Args.length));
            auto r = getAs!(Tuple!R)(i);
            pop(R.length);
            return r;
        }
    }
}

//------------------------------------------------------------------------------
/// Lua のエラー情報を持つ例外
class LuaException : Exception
{
    this(lua_State* l, string msg, string f = __FILE__, size_t ln = __LINE__)
    {
        luaL_where(l, 1);
        size_t len;
        auto str = lua_tolstring(l, -1, &len);
        super(str[0..len].idup ~ msg, f, ln);
    }
}


//------------------------------------------------------------------------------
/// 関数の引数などとして、Lua のテーブルを扱う。中身は std.typecons.Tuple
struct LuaTable(Specs ...)
{
    alias Type = Tuple!Specs;
    Type _payload;
    alias _payload this;

    enum namedMembers = ()
    {
        string[] named;
        foreach (one; Type.fieldNames) if (0 < one.length) named ~= one;
        return named;
    }();

    @trusted @nogc pure nothrow
    this(Type.Types args){ _payload = Type(args); }
}

//------------------------------------------------------------------------------
/**
Lua から呼ばれるD言語の関数の引数として利用すると、
Lua がスタックに積んだ実際のテーブル上にメンバがなくても例外を投げない。
**/
struct LuaTableLoose(Specs ...)
{
    LuaTable!Specs _payload;
    alias _payload this;
}

//------------------------------------------------------------------------------
/** LuaTable のメンバとして使うと、デフォルト値を設定できる。
中身は std.typecons.Typedef.
**/
alias Loosely = Typedef;

//------------------------------------------------------------------------------
/**
LuaState.install により登録され、Lua から呼び出される関数の戻り値として使うと、
Lua への戻り値は既にスタック上に頂上から num 個積まれていることを示す。
**/
alias OnStack = Typedef!int;

//------------------------------------------------------------------------------
/// レジストリへの参照を特に格納する。
alias LuaRegRef = Typedef!int;


//------------------------------------------------------------------------------
// こまごましたのん。
private
template isPublicMethod(T, string N)
{
    import std.traits : isSomeFunction, functionAttributes, FunctionAttribute;
    static
    template _impl(alias F)
    {
        static if (__traits(getProtection, F) == "public" &&
                   isSomeFunction!F &&
                   (functionAttributes!F & FunctionAttribute.property) == 0)
            enum _impl = true;
        else
            enum _impl = false;
    }

    alias isPublicMethod = _impl!(__traits(getMember, T, N));
}

//
private
template isMemberVariable(T, string N)
{
    enum isMemberVariable =
        __traits(getProtection, __traits(getMember, T, N)) == "public" &&
        is(typeof(__traits(getMember, T, N).offsetof));
}

private
template isPropertyMethod(T, string N)
{
    import std.traits : isCallable, functionAttributes, FunctionAttribute;

    static if (__traits(getProtection, __traits(getMember, T, N)) == "public" &&
               isCallable!(__traits(getMember, T, N)) &&
               (functionAttributes!(__traits(getMember, T, N)) &
                FunctionAttribute.property))
        enum isPropertyMethod = true;
    else
        enum isPropertyMethod = false;
}

private
template isGetter(T, string N)
{
    import std.traits : Parameters;
    static if (isPropertyMethod!(T, N))
    {
        enum isGetter =
        {
            foreach (i, one; __traits(getOverloads, T, N))
                if (0 == Parameters!one.length) return true;
            return false;
        }();
    }
    else
        enum isGetter = false;
}

private
template isSetter(T, string N)
{
    import std.traits : Parameters, functionAttributes, FunctionAttribute;
    static if (isPropertyMethod!(T, N))
    {
        enum isSetter =
        {
            foreach (one; __traits(getOverloads, T, N))
            {
                alias Ps = Parameters!one;
                if (1 == Ps.length || 0 == Ps.length &&
                    functionAttributes!one & FunctionAttribute.ref_)
                    return true;
            }
            return false;
        }();
    }
    else
        enum isSetter = false;
}

private
template SetterType(T, string N)
{
    import std.traits : Parameters, functionAttributes, FunctionAttribute;

    enum setterPos =
    {
        foreach (i, one; __traits(getOverloads, T, N))
        {
            alias Ps = Parameters!one;
            if (1 == Ps.length || 0 == Ps.length &&
                functionAttributes!one & FunctionAttribute.ref_)
                return i;
        }
        return -1;
    }();

    static if (isMemberVariable!(T, N))
        alias SetterType = typeof(__traits(getMember, T, N));
    else static if (
        1 == Parameters!(__traits(getOverloads, T, N)[setterPos]).length)
        alias SetterType =
            Parameters!(__traits(getOverloads, T, N)[setterPos])[0];
    else
        alias SetterType = ReturnType!(__traits(getOverloads, T, N)[setterPos]);
}


// alias が取れるような、静的関数をラップする。
extern(C) private
int funcWrapper(alias T)(lua_State* ls) if (__traits(isStaticFunction, T))
{
    scope auto l = new LuaState(ls);
    return callWrapper!T(l);
}

/* Luaから D の関数を呼び出す為のラッパ
引数と戻り値の型でインスタンスが分かれる。
LuaState から引数のpop → 関数本体の呼び出し → 戻り値の push までを行う。
関数 f がタプルを返す場合、中身を展開して、複数個の戻り値として push
される。

Params:
    f = 呼び出される関数本体
*/
private
int callWrapper(T)(LuaState l, T f)
{
    try
    {
        alias Results = ReturnType!T;
        static if      (is(Results : void)) f(getArgs!T(l).expand);
        else static if (is(Results == OnStack))
            return cast(int)f(getArgs!T(l).expand);
        else l.push(f(getArgs!T(l).expand));
        return numTuples!Results;
    }
    catch (Throwable t) l._error(t);
    return 0;
}

/// ditto
private
int callWrapper(alias F)(LuaState l)
{
    try
    {
        alias Results = ReturnType!F;
        static if      (is(Results : void)) F(getArgs!F(l).expand);
        else static if (is(Results == OnStack))
            return cast(int)F(getArgs!F(l).expand);
        else l.push(F(getArgs!F(l).expand));
        return numTuples!Results;
    }
    catch (Throwable t) l._error(t);
    return 0;
}

/// ditto
private
int callWrapper(alias F, T)(LuaState l, T f)
{
    try
    {
        alias Results = ReturnType!T;
        static if     (is(Results : void)) f(getArgs!F(l).expand);
        else static if (is(Results == OnStack))
            return cast(int)f(getArgs!F(l).expand);
        else l.push(f(getArgs!F(l).expand));
        return numTuples!Results;
    }
    catch (Throwable t) l._error(t);
    return 0;
}


/* パッケージ登録の為の、関数名と関数ポインタからなる luaL_Reg を得る。
Params:
    T = struct か class。
*/
private nothrow
luaL_Reg[] memRegs(T)()
{
    enum regsCount =
    {
        uint counter;
        foreach (one; __traits(derivedMembers, T))
            if (isPublicMethod!(T, one)) ++counter;
        return counter;
    }();

    luaL_Reg getReg(string N)()
    {
        static if (__traits(isStaticFunction, __traits(getMember, T, N)))
            return luaL_Reg(N.ptr, &(funcWrapper!(__traits(getMember, T, N))));
        else
            return luaL_Reg(N.ptr, &memWrapper!(T, N));
    }

    auto regs = new luaL_Reg[regsCount+1];
    uint counter;
    foreach (one; __traits(derivedMembers, T))
        static if (isPublicMethod!(T, one)) regs[counter++] = getReg!one;
    return regs;
}

private nothrow
auto metaRegs(T)() if (is(T == class) || is(T == struct))
{
    import std.traits : fullyQualifiedName;
    import std.utf : toUTFz;
    alias toUTF8z = toUTFz!(const(char)*);

    static if      (is(T == class)) alias U = T;
    else static if (is(T == struct)) alias U = T*;

    static extern(C) nothrow
    int _gc(lua_State* l)
    {
        try
        {
            import core.memory: GC;
            auto t = lua_touserdata(l, 1);
            static if      (is(T == struct))
            {
                // dmd2.069.2 crash.
                // destroy(*(cast(T*)t)); //!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! BUG
            }
            else static if (is(T == class)) destroy(cast(T)t);
            else static assert(0, "__gc for " ~ T.stringof ~
                               " is not implemented yet.");
            GC.removeRange(t);
        }
        catch (Throwable) {}
        return 0;
    }

    static extern(C) nothrow
    int _index(lua_State* _l)
    {
        scope auto l = new LuaState(_l);
        try
        {
            auto t = l.getUserDataAs!U(lua_upvalueindex(1));
            auto key = l.getAs!(const(char)[])(-1);
            foreach (one; __traits(derivedMembers, T))
            {
                if (one != key) continue;
                static if (isMemberVariable!(T, one) || isGetter!(T, one))
                {
                    auto top = l.stackTop;
                    l.push(__traits(getMember, t, one));
                    return l.stackTop - top;
                }
            }
            throw new Exception(key.idup ~ " is not a valid member of " ~
                                T.stringof);
        }
        catch (Throwable t) l._error(t);
        return 0;
    }

    static extern(C) nothrow
    int _newindex(lua_State* _l)
    {
        scope auto l = new LuaState(_l);
        try
        {
            auto t = l.getUserDataAs!U(lua_upvalueindex(1));
            auto key = l.getAs!(const(char)[])(-2);
            foreach (one; __traits(derivedMembers, T))
            {
                if (one != key) continue;
                static if (isMemberVariable!(T, one) || isSetter!(T, one))
                {
                    __traits(getMember, t, one) =
                        l.getAs!(SetterType!(T, one))(-1);
                    return 0;
                }
            }
            throw new Exception(key.idup ~ " is not a valid member of " ~
                                T.stringof);
        }
        catch (Throwable t) l._error(t);
        return 0;
    }

    return [luaL_Reg("__gc", &_gc),
            luaL_Reg("__index", &_index),
            luaL_Reg("__newindex", &_newindex),
            luaL_Reg(null, null)];
}


// デリゲートを格納する。
// (デリゲート型から void* へのキャストが非推奨な為のラッパ)
private struct DelContainer(T) {T payload;}

// Lua から 非static な Dの関数を呼び出す為のラッパ
extern(C) private nothrow
int delWrapper(T)(lua_State* ls)
{
    scope auto l = new LuaState(ls);
    try
    {
        auto del = l.getUserDataAs!(DelContainer!T*)(lua_upvalueindex(1));
        return callWrapper(l, del.payload);
    }
    catch (Throwable t) l._error(t);
    return 0;
}

/* 非static なメンバ関数を Lua から呼び出す為のラッパ
Params:
    T = メンバ関数を含む struct か class。
    F = 関数名
*/
extern(C) static nothrow
int memWrapper(T, string F)(lua_State* ls)
{
    static if (is(T U == class) || is(T : U*, U) && is(U == struct)){}
    else static assert(0, "no implementation for " ~ T.stringof);

    scope auto l = new LuaState(ls);
    try
    {
        auto t = l.getUserDataAs!U(lua_upvalueindex(1));
        return callWrapper!(__traits(getMember, U, F))
            (l, &__traits(getMember, t, F));
    }
    catch (Throwable t) l._error(t);
    return 0;
}


/* 引数が lua_State* か、もしくは LuaState だった場合はそれを提供する。

   Throws:
   Exception = 引数の数が足りなかった場合に投げられる。
*/
private
auto getArgs(F...)(LuaState l)
{
    import std.conv : to;
    import std.traits : ParameterTypeTuple, ParameterDefaultValueTuple;

    // 全引数
    alias Args = Tuple!(ParameterTypeTuple!(F[0]));
    // 全デフォルト引数
    alias Defs = ParameterDefaultValueTuple!(F[0]);

    // デフォルト引数のない引数の個数
    template _noDefs(R...)
    {
        static if      (0 == R.length)
            enum _noDefs = 0;
        else static if (is(R[0] == void))
            enum _noDefs = 1 + _noDefs!(R[1..$]);
        else
            enum _noDefs = _noDefs!(R[1..$]);
    }
    alias noDefs = _noDefs!(ParameterDefaultValueTuple!(F[0]));

    // Luaから得るべき引数の個数
    template _vArg(R...)
    {
        static if      (0 == R.length)
            enum _vArg = 0;
        else static if (is(R[0] : LuaState) || is(R[0] : lua_State*))
            enum _vArg = _vArg!(R[1..$]);
        else
            enum _vArg = 1 + _vArg!(R[1..$]);
    }
    alias vnArgs = _vArg!(ParameterTypeTuple!(F[0])[0..noDefs]);

    // 引数の数が足りない場合には例外を投げる。
    if (l.stackTop < vnArgs)
    {
        string name;
        static if (is(typeof(__traits(identifier, F[0]))))
            name = __traits(identifier, F[0]);
        else
            name = "[ANONYMUS]";

        throw new LuaException(l.ptr, "A D function " ~ name ~ " needs " ~
                               vnArgs.to!string ~ " arguments. But " ~
                               "the function was invoked with " ~
                               l.stackTop.to!string ~ " arguments.");
    }

    // 引数の設定
    Args args;
    int shift = 0;
    foreach (int i, ref one; args)
    {
        static if      (is(typeof(one) : LuaState)){ one = l; --shift; }
        else static if (is(typeof(one) : lua_State*))
        { one = l.ptr; --shift; }
        else static if (Defs.length <= i || is(Defs[i] == void))
            one = l.getAs!(typeof(one))(1+i+shift);
        else
            one = l.getAs!(typeof(one))(1+i+shift, Defs[i]);
    }
    return args;
}

// Dの関数の戻り値の数。
private
template numTuples(T)
{
    import std.typecons : isTuple;
    static if      (isTuple!T) enum int numTuples = T.length;
    else static if (is(T == void)) enum int numTuples = 0;
    else enum int numTuples = 1;
}

/// getFunc() の戻り値
private
struct FuncOfLua(const(char)* name, R...)
{
    alias Returns = Tuple!R;
    private const LuaRegRef key;
    private LuaState l;

    private @nogc nothrow
    this(LuaState lua)
    {
        l = lua;
        l.getGlobal(name);
        luaL_checktype(l.ptr, -1, LUA_TFUNCTION);
        key = cast(int)l.getRefRegistry;
    }

    /// 登録された関数の呼び出し。
    Returns opCall(ARGS...)(ARGS args)
    {
        l.rawGetRegistry(key);
        return l.pcall!R(args);
    }
}

/* パニック関数。
exit を呼び出しています。

Stack:
    [-0, +0]

BUG:
    この atpanic関数の処理後、Lua に処理を戻すとクラッシュ。
    -> std.c.stdlib.abort がクラッシュ。
*/
private extern(C) nothrow
int _atpanic(lua_State* l)
{
    import std.stdio : writeln;
    import std.file : append;
    import std.c.stdlib : exit;
    import std.datetime : Clock;

    try
    {
        size_t len;
        auto msg = lua_tolstring(l, -1, &len);
        writeln(msg[0..len]);
        append("lua-atpanic.log", Clock.currTime.toSimpleString ~
               ": " ~ msg[0..len] ~ "\n");
    }
    catch (Throwable){}
    exit(1);
    assert(0);
}










//##################XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX####################
//##################XXXXXXXXXXXXXXX D E B U G XXXXXXXXXXXXXX####################
//##################XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX####################
debug(lua):

enum _VERSION_ = "0.0001(dmd2.096.2)";
enum _AUTHORS_ = "KUMA";
enum _LICENSE_ = "CC0";

enum HEADER = "LuaWD ver." ~ _VERSION_ ~ " written by " ~ _AUTHORS_ ~ ", " ~
    "licensed under " ~ _LICENSE_ ~ ".";

//--------------------------------------
enum script_body =
q{
    p(HEADER);
    p("これは、D言語でLuaを利用する為のライブラリです。")
    p("")
    p("[凡例]")
    p("  以下に於て、D言語のコードを")
    p("  [D]: writeln(\"hello, world!\");")
    p("  というように表します。")
    p("  また、Luaのスクリプトコードを")
    p("  [Lua]: print(\"hello, world!\")")
    p("  というように表します。")

    if not prompt() then return end

    p("[1. D → Lua の変換。]")
    p("  D言語の値を Lua のスタックに積むためには、")
    p("  LuaState.push 関数及び LuaState.setGlobal関数を利用して下さい。")
    p()
    p("  例1: [D]: (new LuaState).push(3.141592).setGlobal(\"PI\");")
    p("       この例では、数値 3.141592 が Luaスクリプト内から \"PI\"")
    p("       という名前で参照できるようになります。")
    p("  例2: [D]: (new LuaState).push!DayOfWeek.setGlobal(\"WEEK\");")
    p("       D言語のシンボルのうち、型情報やaliasを得られるものに関しては")
    p("       テンプレート引数として指定することができます。")
    p()
    p("  LuaState.pushで積むことが出来るデータは、")
    p("    1. bool。")
    p("       例: ture == ", true == get_true())
    p("    2. 整数。")
    p("    3. 数値。")
    p("       例:  π = ", my_pi)
    p("    4. 文字列。")
    p("       例: 今日の日付は = ", today())
    p("    5. 配列。Lua 内では TABLE で表現されます。")
    p("       例: 素数の先頭10個は = ", prime(10))
    p("    6. 連想配列。Lua 内では TABLE で表現されます。")
    p("       例: 日本百名山の名前と標高は = ", hyakumeizan())
    p("    7. lua_CFunction(= extern(C) nothrow int function(lua_State*))型")
    p("       の関数ポインタ、もしくは alias。")
    p("       例: この標準出力関数。")
    p("    8. Dの静的関数。ポインタもしくは alias。")
    p("       例: my_sin(π/4) = ", my_sin(my_pi/4))
    p("       例: my_cos(π/8) = ", my_cos(my_pi/8))
    p("    9. デリゲート")

    if not prompt() then return end

    p("    10. 構造体。Lua 内では TABLE で表現されます。")
    p("        構造体のメンバ変数が TABLE へと格納されます。")
    p("        現在、@property の格納には対応していません。")
    p("        これは、循環参照などに問題がある為です。")
    p("        この構造体の関数を呼び出すことは出きません。")
    p("        関数を呼び出したい場合は次項を利用して下さい。")
    p("        例: 富士山のデータ = ", mt_fuji)
    p("    11. std.typecons.Tuple。")
    p("        Tupleをpushした場合、その中身がスタック上に展開されます。")
    p("        D言語の関数の戻り値として使用した場合には、複数の値を Lua へと")
    p("        返すことが出来ます。")
    p("    12. クラスインスタンス。もしくは構造体へのポインタ。")
    p("        Lua 内では TABLE + METATABLE として表現されます。")
    obj = QueryInterface("MyClass")
    p("        A. メソッドへのアクセス。")
    q("           例: ") obj.print("これはクラスメソッドです。")
    p("        B. メンバ変数へのアクセス。")
    p("           メンバ変数へのアクセスは Lua の index / newindex metamethod")
    p("           へと変換されます。")
    p("           Luaスクリプト内でのメンバ変数への代入が、D言語側の")
    p("           インスタンスに反映されます。")
    p("           例:", obj.name)
    obj.name = "Lua から設定した文字列です。"
    p("              ", obj.getName())
    obj = QueryInterface("MyStruct")
    p("           @property属性を持つD言語のメンバ関数は変数の様にアクセス可能")
    p("           です。")
    p("           例:", obj.name)
    obj.name = "Lua から代入した文字列です。"
    p("              ", obj.name)
    p("     13. enumのalias。")
    p("         例:", MYENUM.ONE)
    if not pcall(function() MYENUM.ONE = 10 end) then
        p("             enum への代入はエラーとなります。")
    end

    if not prompt() then return end

    p("  ## 注意点")
    p("    * 関数ポインタや、デリゲートを用いてpushをした場合、デフォルト引数")
    p("      を利用できません。")
    p("    * Lua内で保存されているインスタンスへの参照はD言語のGCに検知され")
    p("      ません。インスタンスの寿命に注意して下さい。")
    p("      LuaState.newUserData 関数を用いた場合は、インスタンスが Lua の")
    p("      GC によって確保され、D言語の GC.addRange が呼ばれる為")
    p("      Luaスクリプト内でのスコープがインスタンスの寿命となります。")
    p()
    p("  ## !!! バグ !!!")
    p("    * LuaState.newUserData で確保された構造体のデストラクタが")
    p("      実行されません。")
    p("\n")

    if not prompt() then return end

    p("[2. Lua → D言語の変換。]")
    p("  D言語から Lua スタック内の値を取り出すには、")
    p("  LuaState.getAs 関数を利用して下さい。")
    p("  例: [D]: auto val = ls.getAs!Type(-1);")
    p("      この例では、LuaState型の変数である ls を参照し、")
    p("      そのスタックの頂上(インデックス値 -1)の値を Type型に変換して")
    p("      変数 val へと格納しています。")
    p()
    p("  LuaState.getAs から取り出すことができる型は、")
    p("    1. bool。")
    p("    2. 整数。lua_Integer は ptrdiff_t の精度があります。")
    p("    3. 数値。lua_Number は double の精度があります。")
    p("    4. 文字列。文字コードは UTF8 が想定されています。")
    p("       getAs!(const(char)[]) で得た場合、戻り値はLuaが確保した文字列へ")
    p("       のスライスになっています。実体が stack から取り除かれると")
    p("       値は未定義となります。")
    p("       getAs!string で得た場合は idup されたものが返ります。")
    p("       どちらの場合も'\\0'終端が保証されています。")
    p("    5. 静的配列。LuaのTABLEからN個の値を取り出します。")
    p("    6. 動的配列。配列長は、lua_rawlen によって決定されます。")
    p("    7. 連想配列。")
    p("    8. 構造体。public なメンバ変数に値が格納されます。")
    p("       (@propertyを含む)メソッドは無視されます。")
    p("    9. std.typecons.Tuple。スタックから連続した値を取り出します。")
    p("    10. クラスインスタンス。もしくは構造体へのポインタ")
    p("        Dからpushされたインスタンスである必要があります。")

    if not prompt() then return end

    p("[3. D言語からLua内で宣言された関数を呼び出す。]")
    p("  例1: [D]: auto ret = ls.callFunc!(double, int)(\"f\", 10, 20);")
    p("       この例では、LuaState型の変数 ls を参照し、")
    p("       Luaスクリプト内で宣言された \"f\"という名前の関数を")
    p("       引数 (10, 20) で呼び出しています。")
    p("       戻り値は常に std.typecons.Tuple です。上の例では、")
    p("       Tuple!(double, int) が想定されています。")
    p("  例2: [D]: auto f = ls.getFunc(\"f\", double, int);")
    p("       getFunc関数を使うことで、関数への参照を得ることができます。")
    p("       引数は、実際の呼び出し時に解決します。")
    p("  例3:")
    function f (x, y)
       p("    Lua 内で宣言された関数をD言語から呼び出しています。");
       return (x^2 * math.sin(y))/(1-x), 999
    end

    setting = { width = 100, height = 200 }
};

void _sjis_out(string str)
{
    import std.conv : to;
    import std.c.stdio : printf;
    import std.windows.charset : toMBSz;

    printf(toMBSz(str));
}

/// 1. extern(C) で lua_State* を引数とする static な関数。
extern(C) nothrow
int println(lua_State* ls)
{
    import std.array : Appender;
    import std.string : join;

    try
    {
        scope auto l = new LuaState(ls);
        auto numargs = l.stackTop;
        for (int i = 1; i<=numargs; i++)
        {
            _sjis_out(l.getStringAt(i));
            write(" ");
        }
        writeln;
    }
    catch (Throwable){}
    return 0;
}

extern(C) nothrow
int print(lua_State* ls)
{
    import std.array : Appender;
    import std.string : join;

    try
    {
        scope auto l = new LuaState(ls);
        auto numargs = l.stackTop;
        for (int i = 1; i<=numargs; i++)
        {
            _sjis_out(l.getStringAt(i));
            write(" ");
        }
    }
    catch (Throwable){}
    return 0;
}


// 出力の休止
bool prompt()
{
    import std.c.stdio : getchar, printf;
    writeln;
    _sjis_out("-- 続行するには ENTER を、終了するには Q + ENTER を押して"
        "下さい。 --");
    auto c = getchar;
    for (auto b = c; b != '\n'; b = getchar){}
    writeln;
    return c != 'Q' && c != 'q';
}

// Lua へと文字列を返す。
string today()
{
    import std.datetime : Clock;
    return Clock.currTime.toSimpleString;
}

// Lua へと配列を返す
int[] prime(int num)
{
    import std.array : Appender;
    import std.math : sqrt;
    enum MAX = short.max;

    Appender!(int[]) buf;

outer:
    for (int i = 1; i < MAX; ++i)
    {
        for (int j = 1; j < buf.data.length && buf.data[j] ^^ 2 <= i; ++j)
            if (i % buf.data[j] == 0) continue outer;

        buf.put(i);
        if (--num <= 0) break;
    }
    return buf.data;
}

// Lua へと連想配列を返す。
int[string] hyakumeizan()
{ return ["利尻岳": 1719, "羅臼岳": 1661, "斜里岳": 1547]; }


// Lua へと構造体を渡す。
struct Mountain
{
    import std.datetime : DateTime;
    string name;
    int elevation;
    DateTime lastEruption;
    int prominence;
    DateTime firstAscent;
}


// Lua へとクラスを渡す
OnStack queryInterface(LuaState l, string name)
{
    if      (name == "MyClass")
    {
        l.push!MyClass;
        return OnStack(1);
    }
    else if (name == "MyStruct")
    {
        l.push!MyStruct;
        return OnStack(1);
    }
    return OnStack(0);
}

class MyClass
{
    string name = "これは MyClass のメンバ変数です。";

    void print(string msg, string def = "デフォルト引数も可。")
    {
        _sjis_out(msg);
        write(" : ");
        _sjis_out(def);
        writeln;
    }

    string getName()
    {
        return name;
    }

}


struct MyStruct
{
    private string _name = "これは MyStruct のメンバ変数です。";

    @property
    string name() { return _name; }
    @property
    void name(string n) { _name = n; }

}


double l_sin(double d)
{
    import std.math : sin;
    return sin(d);
}

double l_cos(double d){ import std.math : cos; return cos(d); }

//
enum EnumType
{
    ONE = "one",
    TWO = "two",
}

//
version (Windows) extern(Windows) bool SetDllDirectoryW(const(wchar)*);

//
void main()
{
    import std.math : PI, tan;
    import std.datetime : DateTime;

    version (Windows)
    {
        import std.file : thisExePath;
        import std.path : buildPath, dirName;
        import std.utf : toUTF16z;

        version (Win64) enum binDir = "bin64";
        else version (Win32) enum binDir = "bin32";
        SetDllDirectoryW(thisExePath.dirName.buildPath(binDir).toUTF16z);
    }

    auto lua = new LuaState;
    scope(exit) if (lua !is null) lua.clear;
    lua .openlibs
        .push!HEADER.setGlobal("HEADER")

        .push!println.setGlobal("p")
        .push!print.setGlobal("q")
        .push!prompt.setGlobal("prompt")
        .push!(()=>true).setGlobal("get_true")
        .push(PI).setGlobal("my_pi")
        .push!l_sin.setGlobal("my_sin")
        .push(&l_cos).setGlobal("my_cos")
        .push!((double d)=>tan(d)).setGlobal("my_tan")
        .push!today.setGlobal("today")
        .push!prime.setGlobal("prime")
        .push!hyakumeizan.setGlobal("hyakumeizan")
        .push(Mountain("富士", 3776, DateTime(1707, 12, 16), 3776,
                       DateTime(-663, 1, 1))).setGlobal("mt_fuji")
        .push!queryInterface.setGlobal("QueryInterface")
        .push!EnumType.setGlobal("MYENUM")

        // 実行
        .doString(script_body);

    auto r = lua.callFunc!(double, int)("f", 10, 20);
    _sjis_out("    Luaスクリプト内で宣言された関数の戻り値は常にタプルです。 ");
    writeln(r);

    writeln("    conversion of Lua's table to D's tuple, with default value");
    alias T = LuaTable!(int, "width", int, "height", int, "depth");
    lua.getGlobal("setting");
    auto table = lua.getAs!T(-1, T(-999,-999,-999));
    writeln("    ", table);

    write("    optimized lua function call: ");
    auto f = lua.getFunc!("f", double, int)();
    f(200, 300);
}
