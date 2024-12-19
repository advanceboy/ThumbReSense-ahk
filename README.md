# ThumbReSense-ahk

ThumbSense Inspired touchpad shortcut utility software.
This software provides the power of AutoHotKey to give the cursor inertia and the ability to remap keys that are only triggered when the touchpad is touched.

--

ThumbSense インスパイアされたタッチパッドのショートカットユーティリティソフトウェアです。
このソフトは AutoHotKey のパワーにより、カーソルに慣性を与えたり、タッチパッドに触れた時のみ発動するキーのリマップの機能を提供します。

Inertia Mouse Pos / 慣性マウス:
![](/images/inertia.gif)

## Setup

Download `ThumbReSense_v*.exe` from the [releases page](https://github.com/advanceboy/ThumbReSense-ahk/releases) and run

or

Open [ThumbReSense.ah2](./ThumbReSense.ah2) with [AutoHotKey v2.0+](https://www.autohotkey.com/)

## How to Use

While touching the touchpad, the following functions are enabled.

タッチパッドに触れている間、以下の機能が有効になる。

Default Scroll Key:

* `l`

Default Remap:

* `j` : Mouse L Button
* `k` : Mouse R Button
* `h` : Mouse M Button
* `f` : Mouse L Button
* `d` : Mouse R Button
* `g` : Mouse M Button

Default Hotkey:

* `u` : Double Click
* `r` : Double Click
* `;` : Browser Back
* `:` : Browser Forward
* `o` : WheelUp
* `.` : WheelDown
* `XButton1` : Home
* `e` : Home
* `w` : Ctrl+Home
* `XButton2` : End
* `c` : End
* `x` : Ctrl+End
* `z` : Alt+Tab
* `Ctrl`+`q` : Exit This App
* `F2`, `F3` : Sample MessageBox

To customise the behaviour, place `ThumbReSense.ini` in the same location as the executable file.
An example description is given in [ThumbReSense.ini](./ThumbReSense.ini).

動作をカスタマイズするには、実行ファイルと同じ場所に `ThumbReSense.ini` を設置する。
記述例は [ThumbReSense.ini](./ThumbReSense.ini) を参照。

## Known Issue

When touching and releasing the touch screen quickly and repeatedly while remapping to the mouse button, the cursor temporarily stops moving on the touch screen.
This is a problem on the AutoHotKey side, so we expect a fix on the AutoHotKey side.
The workaround is to leave the touch panel touched for a few seconds and it will come back immediately.

マウスボタンにリマップ中に、タッチパネルに触れたり離したりを素早く繰り返すと、一時的にタッチパネルでカーソルが動かなくなる。
これは、 AutoHotKey 側の問題なので AutoHotKey 側の修正に期待したい。
数秒タッチパネルに触れたままにしておくとすぐ復活するのがワークアラウンドだ。

## このソフトに関する日本語の記事

[AutoHotKey v2 で 令和の ThumbSense | Aqua Ware つぶやきブログ](https://aquasoftware.net/blog/?p=2243)
