LuaWD - a Lua Wrapper for D -
=============================

WHAT IS THIS?
-------------
This is a wrapper library of [Lua](http://www.lua.org/) for [D Programming Language](http://dlang.org/).

lua52.dll and sample.exe is for Windows(amd64).

FOR ORDINARY USERS
------------------
Use [LuaD](https://github.com/JakobOvrum/LuaD).

HOW TO BUILD
------------
* Please ensure that dmd can find [DerelictLua](https://github.com/DerelictOrg/DerelictLua).

HOW TO USE
----------

    (new LuaState)                  // initialize
        .push!my_stdout             // push my_stdout to Lua's stack.
        .setGlobal("print")         //
        .doString(                  // invoke a script.
        q{
            print("hello, world!")  -- call D's from Lua
        });

PROPERTIES
----------
| FUNCTIONALITY |    SUPPORT     |
|:-------------:|:---------------|
|Tested OS      | Windows, Linux |

LICENSE
-------
[CC0](https://creativecommons.org/publicdomain/zero/1.0/)

(about lua52.dll, please see [Lua License](http://www.lua.org/license.html))


WANNA BE
--------
* XD


HISTORY
-------
* 2016-01-12 ver.0.0001(dmd2.069.2) the first commit.



* * *

これは？
-------
これは、[D言語](http://dlang.org/)から[Lua](http://www.lua.org/)を
使う為のラッパライブラリです。

付属の lua52.dll と sample.exe は 64bit Windows 用です。

初めての方へ
------------
[LuaD](https://github.com/JakobOvrum/LuaD)を使って下さい。


使い方
------

    (new LuaState)                  // 初期化
        .push!my_stdout             // 関数 my_stdouf への参照をスタックに積む。
        .setGlobal("print")         // 積んでるものをLuaのグローバルへ。
        .doString(                  // スクリプトの実行。
        q{
            print("hello, world!")  -- D言語の関数の呼び出し
        });

ビルド
------
* [DerelictLua](https://github.com/DerelictOrg/DerelictLua)を利用しています。
  import / link できるようにしてください。
* src/sworks/lua.d をプロジェクトに参加させて下さい。


謝辞
----
* [D Programming Language](http://dlang.org/) 用のライブラリです。
* Lua用のバインディングに[DerelictLua](https://github.com/DerelictOrg/DerelictLua)を使っています。


ライセンス
----------
[CC0](https://creativecommons.org/publicdomain/zero/1.0/)

(lua52.dll に関しては[Luaライセンス](http://www.lua.org/license.html)を参照して下さい。)


今後の方針
----------
* (´・ω・`)

履歴
----
* 2016-01-12 ver.0.0001(dmd2.069.2) 初代
