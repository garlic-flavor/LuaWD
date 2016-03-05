# LuaWD - a Lua Wrapper for D -


__Version:__ 0.0003(dmd2.070.2)

__Date:__ 2016-Mar-05 22:43:01

__Authors:__ KUMA


## What is this:
This is a wrapper library of [Lua(http://www.lua.org/)](http://www.lua.org/) for [D Programming Language(http://dlang.org/)](http://dlang.org/).
lua52.dll and sample.exe is for Windows(amd64).


## For ordinary users:
Use [LuaD(https://github.com/JakobOvrum/LuaD)](https://github.com/JakobOvrum/LuaD).


## How to build:
Please ensure that dmd can find [DerelictLua(https://github.com/DerelictOrg/DerelictLua)](https://github.com/DerelictOrg/DerelictLua).


## How to use:
```d
(new LuaState)                  // initialize
    .push!my_stdout             // push my_stdout to Lua's stack.
    .setGlobal("print")         //
    .doString(                  // invoke a script.
    q{
        print("hello, world!")  -- call D from Lua
    });

```


## Properties:
functionarity             |support
--------------------------|--------------------------
Tested OS                 |Windows, Linux
Lua version               |5.2
dmd version               |2.070.2
Low level interfaces      |No, depend on DerelictLua
Capsuled stack operations |partially
Error handling            |partially(*1)



(*1) Any restoration from atpanic function is impossible.


## Type conversion:
D type              |Lua type
--------------------|--------------------
bool                |Bool
ptrdiff_t           |Number
double              |Number
ireal               |N/A
struct              |Table
class               |lightuserdata + Metatable
array               |Table
AA                  |Table
std.typecons.Tuple  |Sequential values on the stack
function/delegate   |function



## Licensed under:
https://creativecommons.org/publicdomain/zero/1.0/
(about lua52.dll, please see [Lua License(http://www.lua.org/license.html)](http://www.lua.org/license.html))


## Wanna be:
- XD



## History:
- 2016-03-05 ver.0.0003(dmd2.070.2) new document.
- 2016-01-15 ver.0.0002(dmd2.069.2) make LuaState struct.
- 2016-01-12 ver.0.0001(dmd2.069.2) the first commit.



* * *


## これは:
これは、[D言語(http://dlang.org/)](http://dlang.org/)から[Lua(http://www.lua.org/)](http://www.lua.org/)を
使う為のラッパライブラリです。
付属の lua52.dll と sample.exe は 64bit Windows 用です。


## 初めての方へ:
[LuaD(https://github.com/JakobOvrum/LuaD)](https://github.com/JakobOvrum/LuaD)を使って下さい。


## 使い方:
```d
(new LuaState)                  // 初期化
    .push!my_stdout             // 関数 my_stdouf への参照をスタックに積む。
    .setGlobal("print")         // 積んでるものをLuaのグローバルスコープへ。
    .doString(                  // スクリプトの実行。
    q{
        print("hello, world!")  -- D言語の関数の呼び出し
    });

```


## 特徴:
機能                               |実装
-----------------------------------|-----------------------------------
テスト環境                         |Windows, Linux
Lua のヴァージョン                 |5.2
dmd のヴァージョン                 |2.070.2
LuaのCインターフェイスへのアクセス |× DerelictLuaを使います。
Luaのスタック操作の隠蔽            |△
エラー処理                         |△(*1)

(*1) atpanic関数からの復帰は不可能です。


## 型変換:
D の型              |Lua の型
--------------------|--------------------
bool                |Bool
ptrdiff_t           |Number
double              |Number
ireal               |N/A
struct              |Table
class               |lightuserdata + Metatable
array               |Table
AA                  |Table
std.typecons.Tuple  |スタック上の連続した値
function/delegate   |function



## ビルド:
- [DerelictLua(https://github.com/DerelictOrg/DerelictLua)](https://github.com/DerelictOrg/DerelictLua)を利用して
  います。 import / link できるようにしてください。
- src/sworks/lua.d をプロジェクトに参加させて下さい。



## 謝辞:
- [D Programming Language(http://dlang.org/)](http://dlang.org/) 用のライブラリです。
- Lua用のバインディングに[DerelictLua(https://github.com/DerelictOrg/DerelictLua)](https://github.com/DerelictOrg/DerelictLua)を使っています。



## ライセンス:
[CC0(https://creativecommons.org/publicdomain/zero/1.0/)](https://creativecommons.org/publicdomain/zero/1.0/)
(lua52.dll に関しては[Luaライセンス(http://www.lua.org/license.html)](http://www.lua.org/license.html)を参照して下さい。)


## 今後の方針:
- (´・ω・`)



## 履歴:
- 2016-03-05 ver.0.0003(dmd2.070.2) 新しいドキュメントに。
- 2016-01-15 ver.0.0002(dmd2.069.2) LuaState を構造体に。
- 2016-01-12 ver.0.0001(dmd2.069.2) 初代



* * *


