#Requires AutoHotkey v2.0

#DllLoad "hid.dll"

s := ThumbSensor()
ini_file_path := A_ScriptDir . "\ThumbReSense.ini"

for key In GetPrivateProfileString(ini_file_path, "Remaps") {
    value := GetPrivateProfileString(ini_file_path, "Remaps", key)
    key := RegExReplace(key, "``(?=;)", "")
    s.AddRemap(key, value)
} else {
    ; Define remaps
    ; see: https://www.autohotkey.com/docs/v2/misc/Remap.htm , https://www.autohotkey.com/docs/v2/KeyList.htm
    s.AddRemap("j", "LButton")
    s.AddRemap("k", "RButton")
    s.AddRemap("h", "MButton")
    s.AddRemap("f", "LButton")
    s.AddRemap("d", "RButton")
    s.AddRemap("g", "MButton")
}

for key In GetPrivateProfileString(ini_file_path, "Hotkeys") {
    value := GetPrivateProfileString(ini_file_path, "Hotkeys", key)
    key := RegExReplace(key, "``(?=;)", "")
    s.AddHotkey(key, value)
} else {
    ; Define hotkeys
    ; see: https://www.autohotkey.com/docs/v2/Hotkeys.htm , https://www.autohotkey.com/docs/v2/KeyList.htm
    s.AddHotkey("u", "Click 2") ; double click
    s.AddHotkey("r", "Click(2)")
    s.AddHotkey(";", "Send '{Browser_Back}'") ; like Alt+Left
    s.AddHotkey(":", "Send('{Browser_Forward}')") ; like Alt+Right
    s.AddHotkey("o", "Send('{WheelUp}')")
    s.AddHotkey(".", "Send('{WheelDown}')")
    s.AddHotkey("XButton1", "Send('{Home}')")
    s.AddHotkey("e", "Send('{Home}')")
    s.AddHotkey("w", "Send('^{Home}')") ; move to top
    s.AddHotkey("XButton2", "Send('{End}')")
    s.AddHotkey("c", "Send('{End}')")
    s.AddHotkey("x", "Send('^{End}')") ; move to end
    s.AddHotkey("z", "Send('!{Tab}')") ; Alt+Tab (switches to the previous window)
    s.AddHotkey("^q", "")
    s.AddHotkey("F2", "MsgBox")
    s.AddHotkey("F3", 'MsgBox(`'any text from ThumbReSense`', "Title: ``"title``"", 0x40136)')
}


s.IsPalmRejectionEnabled := Integer(GetPrivateProfileString(ini_file_path, "Option", "IsPalmRejectionEnabled", "1"))

; Enable swipe scrolling
if Integer(GetPrivateProfileString(ini_file_path, "SwipeScroll", "SwipeScrollEnabled", "1")) {
    swipe_scroll_key := GetPrivateProfileString(ini_file_path, "SwipeScroll", "SwipeScrollKey", "l")
    s.SetSwipeScroll(swipe_scroll_key)
    s.SwipeScrollRatio := Number(GetPrivateProfileString(ini_file_path, "SwipeScroll", "SwipeScrollRatio", "1.0"))

}

; Enable mouse inertia
s.IsInertiaEnabled := Integer(GetPrivateProfileString(ini_file_path, "Inertia", "IsInertiaEnabled", "1"))
s.InertiaConductivity := Number(GetPrivateProfileString(ini_file_path, "Inertia", "InertiaConductivity", "0.95"))
s.InertiaMinInitialSpeed := Number(GetPrivateProfileString(ini_file_path, "Inertia", "InertiaMinInitialSpeed", "10.0"))


s.Start()

class ThumbSensor {
    static WM_INPUT            := 0x00FF
    static WM_MOUSEWHEEL       := 0x020A
    static WM_MOUSEHWHEEL      := 0x020E
    static RIDEV_REMOVE        := 0x00000001
    static RIDEV_PAGEONLY      := 0x00000020
    static RIDEV_INPUTSINK     := 0x00000100
    static RIDI_PREPARSEDDATA  := 0x20000005
    static RID_INPUT           := 0x10000003
    static RIM_TYPEHID         := 2
    static HIDP_STATUS_SUCCESS := 0x00110000
    static HidP_Input          := 0
    static HID_USAGE_PAGE_DIGITIZER      := 0x0D
    static HID_USAGE_DIGITIZER_TOUCH_PAD := 0x05

    static RUN_INERTIA_INTERVAL_MS := 10
    static DEFAULT_INERTIA_CONDUCTIVITY := 0.95
    static DEFAULT_INERTIA_MIN_INITIAL_SPEED := 10.0
    static INT_MIN_VALUE := -2147483648

    __New() {
        this._is_activated := false
        this._is_started := false
        this._palm_rejection := true
        this._swipe_scroll := ""
        this._swipe_scroll_ratio := 1.0
        this._is_inertia_enabled := false
        this._inertia_conductivity := ThumbSensor.DEFAULT_INERTIA_CONDUCTIVITY
        this._inertia_min_initial_speed := ThumbSensor.DEFAULT_INERTIA_MIN_INITIAL_SPEED
        this.CapsResultMap := Map()
        this.pressing_remap_key_map := Map()
        this.mouse_history := MouseHistory()
        this.last_scantime := -1    ; HID 0x0d:0x56 Digitizers Page : Scan Time
        this.last_unix_time_ms := 0 ; system time
        this.scan_current := 0
        this.is_scan_invoked := false
        this.is_pressing_swipe_scroll_key := false
        /** @param {ScanInfo} scan */
        this.swipe_last_scan := 0
        this.swipe_scroll_orientation := ""
        this.swipe_scroll_mod := 0.0
        this.inertia_move_last_time_ms := 0
        this.inertia_move_lastx := ThumbSensor.INT_MIN_VALUE
        this.inertia_move_lasty := ThumbSensor.INT_MIN_VALUE
        this.inertia_move_dx := 0
        this.inertia_move_dy := 0
        this.inertia_move_fixed_counter := 0
        this.inertia_move_RunInertia_timer_callback := ObjBindMethod(this, "RunInertia")
        this.err_counter := 0
        this.counter := 0
    }
    Start() {
        if !this._is_started {
            ; If this.OnRawInput is given to callback directly, exception: "Error: Invalid callback function" is thrown.
            ; Because it has a hidden first parameter named `this`.
            ; see: https://www.autohotkey.com/docs/v2/Objects.htm#Custom_Classes_method
            OnMessage(ThumbSensor.WM_INPUT, ObjBindMethod(this, "OnRawInput"))
            if this._RegisterRawInputDevices(ThumbSensor.HID_USAGE_PAGE_DIGITIZER, ThumbSensor.HID_USAGE_DIGITIZER_TOUCH_PAD) !== true {
                throw Error("Faild: RegisterRawInputDevices")
            }

            this._is_started := true
        }
    }
    IsActivated {
        get => this._is_activated
        set {
            if this._is_activated !== Value {
                this._is_activated := Value
                if Value {
                    ; tipped
                    this.err_counter := 0
                    this.StopInertia()
                } else {
                    ; untipped
                    avg := this.mouse_history.GetAverageVectorLast(100, 30)
                    if Type(avg) == "MousePos" {
                        this.SetInertia(avg)
                    }
                    this.mouse_history.Clear()
                }
            }
        }
    }
    IsPalmRejectionEnabled {
        set => this._palm_rejection := Value
    }
    SwipeScrollRatio {
        set => this._swipe_scroll_ratio := Value
    }
    IsInertiaEnabled {
        set => this._is_inertia_enabled := Value
    }
    /**
     * rate of decrease in speed per 10ms
     * @type {Number}
     */
    InertiaConductivity {
        set {
            if Value < 0.0 || 1.0 < Value {
                throw Error('The parameter "InertiaConductivity" is out of range. It must be between 0.0 and 1.0.')
            }
            this._inertia_conductivity := Value
        }
    }
    /**
     * If the pointer speed (per 10ms) during the last 100ms falls below this value, mouse inertia does not work
     * @type {Number}
     */
    InertiaMinInitialSpeed {
        set => this._inertia_min_initial_speed := Value
    }
    AddRemap(key, remap) {
        _this := this
        key_name := GetKeyName(key)
        remap_name := GetKeyName(remap)
        if RegExMatch(remap_name, "^(?:[LRM]Button|XButton\d+|Wheel(?:Down|Up|Left|Right))$") {
            set_delay_func := SetMouseDelay
        } else {
            set_delay_func := SetKeyDelay
        }

        if key_name == "" {
            throw Error("invalid key name: " . key)
        }
        HotIfCallbackClosureForDown(HotkeyName) {
            return _this.IsActivated
        }
        HotIfCallbackClosureForUp(HotkeyName) {
            return _this.IsActivated || _this.pressing_remap_key_map.Has(key_name)
        }
        ; remap implementation using hotkey
        ; see: https://ahkscript.github.io/ja/docs/v2/misc/Remap.htm#remarks
        RemapDownCallbackClosure(HotkeyName) {
            if !_this.pressing_remap_key_map.Has(key_name) {
                set_delay_func(-1)
                Send("{Blind}{" . remap . " DownR}")
                _this.pressing_remap_key_map.Set(key_name, 0)
            }
        }
        RemapUpCallbackClosure(HotkeyName) {
            set_delay_func(-1)
            Send("{Blind}{" . remap . " Up}")
            if _this.pressing_remap_key_map.Has(key_name) {
                _this.pressing_remap_key_map.Delete(key_name)
            }
        }
        HotIf(HotIfCallbackClosureForDown)
        Hotkey("*" . key, RemapDownCallbackClosure)
        HotIf(HotIfCallbackClosureForUp)
        Hotkey("*" . key . " up", RemapUpCallbackClosure)
        HotIf() ; end HotIf
    }
    AddHotkey(key, Action) {
        _this := this

        ; Parse Action
        pos := 1
        if (n := RegExMatch(Action, "i)^\s*([a-zA-Z]\w*)(?:(\()\s*|\s+|\s*$)", &m)) !== 0 {
            func_name := m[1]
            has_parenthesis := m[2] == "("
            func_t := %func_name% ; Get Func Like Object
            pos += StrLen(m[0])
            
            if (n := RegExMatch(Action, "i)(`"(?:[^`"]|(?<=``)`")*`"|'(?:[^']|(?<=``)')*'|0x[0-9a-f]+|\d+(?:\.\d+)?)(?=\W|$)", &m, pos)) !== 0 {
                arg := m[1]
                if Ord(arg) == 0x22 || Ord(arg) == 0x27 {
                    func_t := func_t.Bind(RegExReplace(SubStr(arg, 2, -1), "``(?=[``;:{nrbtsvaf'`"])", "")) ; remove quoting and escaping
                } else {
                    func_t := func_t.Bind(0 + arg)
                }
                pos += StrLen(m[0])
                while (n := RegExMatch(Action, "i)\s*,\s*(`"(?:[^`"]|(?<=``)`")*`"|'(?:[^']|(?<=``)')*'|0x[0-9a-f]+|\d+(?:\.\d+)?)(?=\W|$)", &m, pos)) !== 0 {
                    arg := m[1]
                    if Ord(arg) == 0x22 || Ord(arg) == 0x27 {
                        func_t := func_t.Bind(RegExReplace(SubStr(arg, 2, -1), "``(?=[``;:{nrbtsvaf'`"])", "")) ; remove quoting and escaping
                    } else {
                        a:=0 + arg
                        func_t := func_t.Bind(0 + arg)
                    }
                    pos += StrLen(m[0])
                }
            }
            if has_parenthesis {
                if RegExMatch(Action, "\s*\)\s*$", &m, pos) == 0 {
                    throw ValueError("Invalid Action: " . Action)
                }
            } else {
                if RegExMatch(Action, "\s*$", &m, pos) == 0 {
                    throw ValueError("Invalid Action: " . Action)
                }
            }
        } else {
            throw ValueError("Invalid Action: " . Action)
        }
        
        HotIfCallbackClosure(HotkeyName) {
            return _this.IsActivated
        }
        HotkeyCallbackClosure(HotkeyName) {
            func_t.Call()
        }
        HotIf(HotIfCallbackClosure)
        Hotkey(key, HotkeyCallbackClosure)
        HotIf()
    }

    SetSwipeScroll(key) {
        _this := this
        key_name := GetKeyName(key)
        if key_name == "" {
            throw Error("invalid key name: " . key)
        }

        HotIf(HotkeyName => _this.IsActivated)
        Hotkey("*" . key, ObjBindMethod(this, "_OnSwipeScrollKeyDown"))
        HotIf(HotkeyName => _this.IsActivated || _this.is_pressing_swipe_scroll_key)
        Hotkey("*" . key . " up", ObjBindMethod(this, "_OnSwipeScrollKeyUp"))
        HotIf() ; end HotIf
    }
    _OnSwipeScrollKeyDown(HotKeyName) {
        if !this.is_pressing_swipe_scroll_key {
            this.is_pressing_swipe_scroll_key := true
            this.swipe_last_scan := 0
            this.swipe_scroll_orientation := ""
            this.swipe_scroll_mod := 0.0
            BlockInput("MouseMove")
        }
    }
    _OnSwipeScrollKeyUp(HotKeyName) {
        this.is_pressing_swipe_scroll_key := false
        BlockInput("MouseMoveOff")
    }
    /** @param {ScanInfo} scan */
    _OnSwipeScrollScanCompleted(scan, mouse_pos_x, mouse_pos_y) {
        if this.swipe_last_scan {
            ; identify the most moved contact
            max_diff_x := 0
            max_diff_y := 0
            contact_cur_ids := scan.GetTouching(this._palm_rejection)
            contact_cur_map := scan.GetContactMap(this._palm_rejection)
            contact_last_map := this.swipe_last_scan.GetContactMap(this._palm_rejection)
            for id IN contact_cur_ids {
                if contact_last_map.Has(id) {
                    ; intercected list
                    diff_x := contact_cur_map[id].touch_pos_x - contact_last_map[id].touch_pos_x
                    if Abs(max_diff_x) < Abs(diff_x) {
                        max_diff_x := diff_x
                    }
                    diff_y := contact_cur_map[id].touch_pos_y - contact_last_map[id].touch_pos_y
                    if Abs(max_diff_y) < Abs(diff_y) {
                        max_diff_y := diff_y
                    }
                }
            }

            ; post wheel msg
            pos := Buffer()
            hWnd := DllCall("WindowFromPoint", "UInt64", (mouse_pos_y<<32)|(mouse_pos_x&0xffffffff), "Ptr")
            if this.swipe_scroll_orientation == "" {
                if Abs(max_diff_x) > Abs(max_diff_y) {
                    this.swipe_scroll_orientation := "H"
                } else {
                    this.swipe_scroll_orientation := "V"
                }
            }
            if this.swipe_scroll_orientation == "V" {
                scroll_count_float := max_diff_y * this._swipe_scroll_ratio + this.swipe_scroll_mod
                scroll_count := Integer(scroll_count_float)
                this.swipe_scroll_mod := scroll_count_float - scroll_count
                PostMessage(ThumbSensor.WM_MOUSEWHEEL, scroll_count << 16, (mouse_pos_y<<16)|mouse_pos_x, hWnd)
            } else if this.swipe_scroll_orientation == "H" {
                scroll_count_float := max_diff_x * this._swipe_scroll_ratio + this.swipe_scroll_mod
                scroll_count := Integer(scroll_count_float)
                this.swipe_scroll_mod := scroll_count_float - scroll_count
                PostMessage(ThumbSensor.WM_MOUSEHWHEEL, scroll_count << 16, (mouse_pos_y<<16)|mouse_pos_x, hWnd)
            }
        }
        this.swipe_last_scan := scan
    }

    /**
     * @param {MousePos} mouse_avg 
     */
    SetInertia(mouse_avg) {
        if this._is_inertia_enabled {
            speed := Sqrt(mouse_avg.mouse_pos_x ** 2 + mouse_avg.mouse_pos_y ** 2) * 10
            if speed > this._inertia_min_initial_speed {
                this.inertia_move_last_time_ms := GetCurrentUnixTimeMilliseconds()
                this.inertia_move_lastx := ThumbSensor.INT_MIN_VALUE
                this.inertia_move_lasty := ThumbSensor.INT_MIN_VALUE
                this.inertia_move_dx := mouse_avg.mouse_pos_x
                this.inertia_move_dy := mouse_avg.mouse_pos_y
                this.inertia_move_fixed_counter := 0
                SetTimer(this.inertia_move_RunInertia_timer_callback, ThumbSensor.RUN_INERTIA_INTERVAL_MS, 1000)
            }
        }
    }
    StopInertia() {
        SetTimer(this.inertia_move_RunInertia_timer_callback, 0)
    }

    RunInertia() {
        Critical("On")
        current_time_ms := GetCurrentUnixTimeMilliseconds()
        diff_time_ms := current_time_ms - this.inertia_move_last_time_ms
        this.inertia_move_last_time_ms := current_time_ms

        ; MouseGetPos and MouseMove do not work well with window scaling or multiscreen
        ThumbSensor.GetCursorPos(&pos_x, &pos_y)
        if this.inertia_move_lastx == ThumbSensor.INT_MIN_VALUE {
            this.inertia_move_lastx := pos_x
        }
        if this.inertia_move_lasty == ThumbSensor.INT_MIN_VALUE {
            this.inertia_move_lasty := pos_y
        }
        dx_float := this.inertia_move_dx * diff_time_ms + pos_x - this.inertia_move_lastx
        dy_float := this.inertia_move_dy * diff_time_ms + pos_y - this.inertia_move_lasty
        dx := Round(dx_float)
        dy := Round(dy_float)
        if dx == 0 && dy == 0 {
            this.inertia_move_fixed_counter += 1
            if this.inertia_move_fixed_counter >= 7 {
                this.StopInertia()
                return
            }
        } else {
            this.inertia_move_fixed_counter := 0
            ThumbSensor.SetCursorPos(pos_x + dx, pos_y + dy)
        }
        ThumbSensor.GetCursorPos(&pos_x, &pos_y)
        this.inertia_move_lastx := pos_x - dx_float + dx
        this.inertia_move_lasty := pos_y - dy_float + dy
        conductivity := this._inertia_conductivity ** (diff_time_ms/10)
        this.inertia_move_dx *= conductivity
        this.inertia_move_dy *= conductivity
    }

    static GetCursorPos(&pos_x, &pos_y) {
        buf := Buffer(8, 0)
        if DllCall("GetCursorPos", "Ptr", buf.Ptr, "UChar") == 0 {
            throw Error("GetCursorPos returns nonzero")
        }
        pos_x := NumGet(buf, 0, "Int")
        pos_y := NumGet(buf, 4, "Int")
    }

    static SetCursorPos(pos_x, pos_y) {
        if DllCall("SetCursorPos", "Int", pos_x, "Int", pos_y, "UChar") == 0 {
            throw Error("SetCursorPos returns nonzero")
        }
    }

    /**
     * Once all Contacts that have all the same ScanTime is available from multiple HID reports
     * Interpretation of Windows : https://learn.microsoft.com/windows-hardware/design/component-guidelines/touchpad-windows-precision-touchpad-collection
     * @param {ScanInfo} scan 
     */
    OnScanCompleted(scan) {
        ; set the IsActivated for HotIf
        touching_list := scan.GetTouching(this._palm_rejection)
        ; store mous pos history
        if (scan.unix_time_ms - this.last_unix_time_ms) >= 5 {
            ThumbSensor.GetCursorPos(&mouse_pos_x, &mouse_pos_y)
            this.last_unix_time_ms := scan.unix_time_ms
            this.mouse_history.Push(mouse_pos_x, mouse_pos_y, scan)
        }
        
        this.IsActivated := touching_list.Length !== 0

        if this.is_pressing_swipe_scroll_key {
            this._OnSwipeScrollScanCompleted(scan, mouse_pos_x, mouse_pos_y)
        }
    }

    /**
     * If different HID reports have the same Scan Time (Usage Page: 0x0d (Digitizers), Usage Id: 0x56), we should be treated as information from the same frame.
     * https://learn.microsoft.com/windows-hardware/design/component-guidelines/single-finger-hybrid-mode-report-descriptor
     * https://learn.microsoft.com/windows-hardware/design/component-guidelines/two-finger-parallel-hybrid-mode-report-descriptor
     * @param {RawInputHidData} input_hid_data 
     */
    AnalyzeReport(input_hid_data) {
        caps_result := this._GetRawInputPreparsedCapabilities(input_hid_data.Header_hDevice)
        if IsNumber(caps_result) {
            return ; failed
        }

        scantime := this._GetUsageValue(0x0d, 0, 0x56, input_hid_data) ; 0x0d:0x56 Digitizers Page : Scan Time
        if this.last_scantime !== scantime {
            if !this.is_scan_invoked && Type(this.scan_current) == "ScanInfo" {
                ; if the `scantime` is changed before all contacts have been reported:
                this.OnScanCompleted(this.scan_current)
            }
            this.is_scan_invoked := false
            contact_count := this._GetUsageValue(0x0d, 0, 0x54, input_hid_data) ; 0x0d:0x54 Digitizers Page : Contact Count
            this.scan_current := ScanInfo(contact_count)
            this.last_scantime := scantime
        }

        contact_id_list := Map()
        for index in caps_result.ValidCollectionIndexes {
            contact_id := this._GetUsageValue(0x0d, index, 0x51, input_hid_data) ; 0x0d:0x51 Digitizers Page : Contact Identifier
            if contact_id_list.Has(contact_id) {
                break
            }
            ; only first valid contact id
            contact_id_list.Set(contact_id, 0)

            is_tipped := false
            is_confided := false
            for b in this._GetUsagesButtons(index, input_hid_data) {
                if b.UsagePage == 0x0d && b.Usage == 0x42 { ; 0x0d:0x42 Digitizers Page : Tip Switch
                    is_tipped := true
                    
                } else if b.UsagePage == 0x0d && b.Usage == 0x47 { ; 0x0d:0x47 Digitizers Page : Touch Valid/Confidence
                    is_confided := true
                }
            }
            pos_x := this._GetUsageValue(0x01, index, 0x30, input_hid_data) ; 0x01:0x30 Generic Desktop Page : X
            pos_y := this._GetUsageValue(0x01, index, 0x31, input_hid_data) ; 0x01:0x30 Generic Desktop Page : Y
            this.scan_current.PushContact(ContactInfo(contact_id, is_tipped, is_confided, pos_x, pos_y))
        }
        if this.scan_current.IsFullContact() {
            this.is_scan_invoked := true
            this.OnScanCompleted(this.scan_current)
        }
    }

    OnRawInput(wParam, lParam, msg, hwnd) { ; WM_INPUT
        Critical("On")
        try {
            ri_hid_result := this._GetRawInputHidData(lParam)
            if (!IsNumber(ri_hid_result)) {
                    this.AnalyzeReport(ri_hid_result)
            }
        } catch as err {
            this.err_counter += 1
            if this.err_counter > 255 {
                throw err
            }
        }
        return DllCall("DefWindowProcW", "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }

    /**
     * @param {Integer} UsagePage 
     * @param {Integer} LinkCollection 
     * @param {Integer} Usage 
     * @param {RawInputHidData} input_hid_data 
     * @returns {Integer}
     */
    _GetUsageValue(UsagePage, LinkCollection, Usage, input_hid_data) {
        caps_result := this._GetRawInputPreparsedCapabilities(input_hid_data.Header_hDevice)
        usage_value := 0
        hidp_result := DllCall("hid\HidP_GetUsageValue", "Int", ThumbSensor.HidP_Input, "UShort", UsagePage, "UShort", LinkCollection, "UShort", Usage, "UintP", &usage_value, "Ptr", caps_result.PreparsedData, "Ptr", input_hid_data.Data_rawData, "UInt", input_hid_data.Data_rawData.Size, "Int")
        if hidp_result !== ThumbSensor.HIDP_STATUS_SUCCESS {
            ; rarely this error occurs
            ; e.g. -1072627709 = 0xC0110003: HIDP_STATUS_INVALID_REPORT_LENGTH
            throw Error("HidP_GetUsageValue raises Error: " . hidp_result)
        }
        return usage_value
    }
    /**
     * @param LinkCollection 
     * @param input_hid_data 
     * @returns {Array<Integer, UsageAndPage>}
     */
    _GetUsagesButtons(LinkCollection, input_hid_data) {
        caps_result := this._GetRawInputPreparsedCapabilities(input_hid_data.Header_hDevice)
        buttons_list_buf := Buffer(UsageAndPage.STRUCT_LENGTH * caps_result.ButtonCaps.Length)
        buttons_list_length := caps_result.ButtonCaps.Length
        hidp_result := DllCall("hid\HidP_GetUsagesEx", "Int", ThumbSensor.HidP_Input, "UShort", LinkCollection, "Ptr", buttons_list_buf.Ptr, "UintP", &buttons_list_length, "Ptr", caps_result.PreparsedData, "Ptr", input_hid_data.Data_rawData, "UInt", input_hid_data.Data_rawData.Size, "Int")
        if hidp_result !== ThumbSensor.HIDP_STATUS_SUCCESS {
            throw Error("HidP_GetUsagesEx raises Error")
        }
        return UsageAndPage.FromButtonListBuffer(buttons_list_buf)
    }
    /** @returns {RawInputHidData} */
    _GetRawInputHidData(handle) { ; set lParam of WM_INPUT message
        ri_header_size := 8 + (A_PtrSize * 2)
        dw_size := 0
        DllCall("GetRawInputData", "Ptr", handle, "UInt", ThumbSensor.RID_INPUT, "Ptr", 0, "UIntP", &dw_size, "UInt", ri_header_size)
        if (dw_size) {
            buf := Buffer(dw_size, 0) ; 
            if (DllCall("GetRawInputData", "Ptr", handle, "UInt", ThumbSensor.RID_INPUT, "Ptr", buf.Ptr, "UIntP", &dw_size, "UInt", ri_header_size) == dw_size) {
                dwType := NumGet(buf, 0, "UInt") ; ((RAWINPUT)buf).header.dwType: DWORD
                if (dwType == ThumbSensor.RIM_TYPEHID) {
                    ri := RawInputHidData(buf)
                    return ri
                } ; ignore if dwType == RIM_TYPEMOUSE || dwType == RIM_TYPEKEYBOARD
            }
        }
        return false
    }
    /** @returns {CapsResult} */
    _GetRawInputPreparsedCapabilities(hdevice) {
        ; search from cache
        if this.CapsResultMap.Has(hdevice) {
            return this.CapsResultMap.Get(hdevice)
        }
        
        dw_size := 0
        if DllCall("GetRawInputDeviceInfoW", "Ptr", hdevice, "UInt", ThumbSensor.RIDI_PREPARSEDDATA, "Ptr", 0, "UIntP", &dw_size, "UInt") !== 0 {
            return false
        }
        preparseddata_buf := Buffer(dw_size, 0)
        if DllCall("GetRawInputDeviceInfoW", "Ptr", hdevice, "UInt", ThumbSensor.RIDI_PREPARSEDDATA, "Ptr", preparseddata_buf.Ptr, "UIntP", &dw_size, "UInt") !== dw_size {
            return false
        }

        ; parse capabilities
        capabilities_buf := Buffer(HidpCaps.STRUCT_LENGTH, 0)
        if DllCall("hid\HidP_GetCaps", "Ptr", preparseddata_buf.Ptr, "Ptr", capabilities_buf.Ptr, "Int") !== ThumbSensor.HIDP_STATUS_SUCCESS {
            return false
        }
        capabilities := HidpCaps(capabilities_buf)

        buttoncapslength := capabilities.NumberInputButtonCaps
        buttoncaps_buf := Buffer(HidpButtonCaps.STRUCT_LENGTH * buttoncapslength, 0)
        if DllCall("hid\HidP_GetButtonCaps", "Int", ThumbSensor.HidP_Input, "Ptr", buttoncaps_buf.Ptr, "UShortP", &buttoncapslength, "Ptr", preparseddata_buf.Ptr, "Int") !== ThumbSensor.HIDP_STATUS_SUCCESS {
            return false
        }
        buttoncaps := HidpButtonCapsArray(buttoncaps_buf)

        valuecapslength := capabilities.NumberInputValueCaps
        valuecaps_buf := Buffer(HidpValueCaps.STRUCT_LENGTH * valuecapslength, 0)
        if DllCall("hid\HidP_GetValueCaps", "Int", ThumbSensor.HidP_Input, "Ptr", valuecaps_buf.Ptr, "UShortP", &valuecapslength, "Ptr", preparseddata_buf.Ptr, "Int") !== ThumbSensor.HIDP_STATUS_SUCCESS {
            return false
        }
        valuecaps := HidpValueCapsArray(valuecaps_buf)

        ; calc 
        valid_Collection_indexes := ArraySortable()
        for valcap in valuecaps {
            /** @type {HidpValueCaps} */
            valcap := valcap
            if valcap.UsagePage == 0x0d && valcap.NotRangeUsage == 0x51 {
                valid_Collection_indexes.Push(valcap.LinkCollection)
            }
        }
        valid_Collection_indexes.Sort()

        ; cache result
        result := CapsResult(preparseddata_buf, buttoncaps, valuecaps, valid_Collection_indexes)
        this.CapsResultMap.Set(hdevice, result)
        return result
    }
    _RegisterRawInputDevices(Page, Usage) {
        struct_size := 8 + A_PtrSize ; size of a RAWINPUTDEVICE structure
        flags := ThumbSensor.RIDEV_INPUTSINK
        HGUI := A_ScriptHwnd
        rid := Buffer(struct_size, 0) ; RAWINPUTDEVICE structure
        NumPut("UShort", Page,  rid, 0)
        NumPut("UShort", Usage, rid, 2)
        NumPut("UInt",   flags, rid, 4)
        NumPut("Ptr",    HGUI,  rid, 8)
        return DllCall("RegisterRawInputDevices", "Ptr", rid.Ptr, "UInt", 1, "UInt", struct_size, "Int")
    }
    _UnRegisterRawInputDevices(Page, Usage) {
        struct_size := 8 + A_PtrSize ; size of a RAWINPUTDEVICE structure
        flags := ThumbSensor.RIDEV_REMOVE | (Usage == 0 ? ThumbSensor.RIDEV_PAGEONLY : 0x00)
        rid := Buffer(struct_size, 0) ; RAWINPUTDEVICE structure
        NumPut("UShort", Page,  rid, 0)
        NumPut("UShort", Usage, rid, 2)
        NumPut("UInt",   flags, rid, 4)
        return DllCall("RegisterRawInputDevices", "Ptr", rid.Ptr, "UInt", 1, "UInt", struct_size, "Int")
     }
}
class MousePos {
    __New(mouse_pos_x, mouse_pos_y, scan) {
        this.mouse_pos_x := mouse_pos_x
        this.mouse_pos_y := mouse_pos_y
        /** @type {ScanInfo} */
        this.scan := scan
    }
}
class MouseHistory {
    static BUFFER_LENGTH := 128
    __New() {
        /** @type {Array<Integer, MousePos>} */
        this._buffer := Array()
        this._buffer.Length := MouseHistory.BUFFER_LENGTH
        this._start_idx_zero_started := 0
        this._looping := false
    }
    _increment() {
        this._start_idx_zero_started += 1
        modded := Mod(this._start_idx_zero_started, MouseHistory.BUFFER_LENGTH)
        if modded !== this._start_idx_zero_started {
            this._looping := true
            this._start_idx_zero_started := modded
        }
        return this._start_idx_zero_started + 1
    }
    Push(mouse_pos_x, mouse_pos_y, scan) {
        this._buffer[this._start_idx_zero_started + 1] := MousePos(mouse_pos_x, mouse_pos_y, scan)
        this._increment()
    }
    Clear() {
        this._start_idx_zero_started := 0
        this._looping := false
    }
    /**
     * get a vector of average velocities during the specified time span
     * return `false` if the history length is shorter than %least_ms%
     * @param {Integer} ms
     * @param {Integer} least_ms
     * @returns {MousePos}
     */
    GetAverageVectorLast(ms, least_ms) {
        if !this._looping && this._start_idx_zero_started == 0 {
            return 0
        } 
        toloop := this._looping
        if this._start_idx_zero_started == 0 {
            cur_idx_zero_started := MouseHistory.BUFFER_LENGTH - 1
            toloop := false
        } else {
            cur_idx_zero_started := this._start_idx_zero_started - 1
        }
        last_pos := this._buffer[cur_idx_zero_started + 1]
        last_ms := last_pos.scan.unix_time_ms
        cur_pos := this._buffer[cur_idx_zero_started + 1]
        ; go back to start position or %ms% time ago
        loop {
            cur_idx_zero_started -= 1
            if cur_idx_zero_started <= 0 {
                if toloop {
                    cur_idx_zero_started := MouseHistory.BUFFER_LENGTH - 1
                    toloop := false
                } else {
                    return this._calcVector(last_pos, cur_pos, least_ms)
                }
            }
            cur_pos := this._buffer[cur_idx_zero_started + 1]
            if ms < (last_ms - cur_pos.scan.unix_time_ms) {
                return this._calcVector(last_pos, cur_pos, least_ms)
            }
        }

    }
    /**
     * @param {MousePos} last_pos
     * @param {MousePos} cur_pos
     * @param {Integer} least_ms
     * @returns {MousePos}
     */
    _calcVector(last_pos, cur_pos, least_ms) {
        diff_ms := last_pos.scan.unix_time_ms - cur_pos.scan.unix_time_ms
        if diff_ms < least_ms {
            return false
        }
        return MousePos((last_pos.mouse_pos_x - cur_pos.mouse_pos_x) / diff_ms, (last_pos.mouse_pos_y - cur_pos.mouse_pos_y) / diff_ms, diff_ms)
    }
}
class UsageAndPage {
    static STRUCT_LENGTH := 4
    __New() {
        this._buf := Buffer(UsageAndPage.STRUCT_LENGTH, 0)
    }
    Ptr => this._buf.Ptr
    ; USAGE_AND_PAGE 
    ; https://learn.microsoft.com/windows-hardware/drivers/ddi/hidpi/ns-hidpi-_usage_and_page
    ; typedef struct _USAGE_AND_PAGE {
    ;   USAGE Usage;     (u16)
    ;   USAGE UsagePage; (u16)
    ; } USAGE_AND_PAGE
    Usage => NumGet(this._buf, 0, "UShort")
    UsagePage => NumGet(this._buf, 2, "UShort")
    /**
     * @param buf 
     * @returns {Array<Integer, UsageAndPage>}
     */
    static FromButtonListBuffer(buf) {
        if Type(buf) !== "Buffer" || Mod(buf.Size, UsageAndPage.STRUCT_LENGTH) !== 0 {
            throw Error("unexpected argument: buf")
        }
        buttons_list_length := buf.Size // UsageAndPage.STRUCT_LENGTH
        result := Array()
        result.Capacity := buttons_list_length
        loop buttons_list_length {
            offset := A_Index - 1
            unp := UsageAndPage()
            DllCall("RtlMoveMemory", "Ptr", unp.Ptr, "Ptr", buf.Ptr + (UsageAndPage.STRUCT_LENGTH * offset), "UPtr", UsageAndPage.STRUCT_LENGTH)
            result.Push(unp)
        }
        return result
    }
}
class ContactInfo {
    __New(contact_id, is_tipped, is_confided, touch_pos_x, touch_pos_y) {
        this.contact_id := contact_id
        this.is_tipped := is_tipped
        this.is_confided := is_confided
        this.touch_pos_x := touch_pos_x
        this.touch_pos_y := touch_pos_y
    }
}
class ScanInfo {
    __New(contact_count) {
        /** @type {Array<Integer, ContactInfo>} */
        this._array := Array()
        this._contact_count := contact_count
        this.unix_time_ms := GetCurrentUnixTimeMilliseconds()
    }
    /** @param {ContactInfo} contact_info */
    PushContact(contact_info) {
        this._array.Push(contact_info)
    }
    IsFullContact() {
        return this._array.Length >= this._contact_count
    }
    /**
     * Get touching contact_id array
     * @param {Integer} palm_rejection
     * @returns {Array<Integer, Integer>}
     */
    GetTouching(palm_rejection) {
        ret := Array()
        for c IN this._array {
            if palm_rejection && c.is_tipped && c.is_confided || !palm_rejection && c.is_tipped {
                ret.Push(c.contact_id)
            }
        }
        return ret
    }
    /**
     * Get touching contact_id to scan map
     * @param {Integer} palm_rejection
     * @returns {Map<String, ContactInfo>}
     */
    GetContactMap(palm_rejection) {
        ret := Map()
        for c IN this._array {
            if palm_rejection && c.is_tipped && c.is_confided || !palm_rejection && c.is_tipped {
                ret.Set(c.contact_id, c)
            }
        }
        return ret
    }
}
GetCurrentUnixTimeMilliseconds() {
    buf := Buffer(8, 0) ; FILETIME
    DllCall("GetSystemTimeAsFileTime", "Ptr", buf.Ptr)
    filetime_millisecond := (NumGet(buf, 0, "UInt") // 10000) + ((NumGet(buf, 4, "UInt") << 28) // 625) ; FILETIME.dwHighDateTime // 10000 + (FILETIME.dwHighDateTime << 32) // 10000 without overflows
    return filetime_millisecond - 11644473600000
}
GetPrivateProfileString(FileName, AppName, KeyName := unset, Default := unset) {
    ; IniRead of ahk is not user friendly, so direct win32 api call
    char_len := 4096
    if IsSet(KeyName) {
        type_keyName := "Str"
        val_keyName := KeyName
    } else {
        type_keyName := "Ptr"
        val_keyName := 0
    }
    loop 4 {
        bufW := Buffer(char_len * 2)
        nret_len := DllCall("GetPrivateProfileStringW", "Str", AppName, type_keyName, val_keyName, "Ptr", 0, "Ptr", bufW.Ptr, "Int", char_len, "Str", FileName, "Int")
        if (IsSet(KeyName) && nret_len - 1 == char_len) || (nret_len - 2 >= char_len) {
            char_len *= 2
            continue
        }
        break
    }
    if IsSet(KeyName) {
        ret_value := StrGet(bufW)
        if ret_value == "" && IsSet(Default) {
            return Default
        } else {
            return ret_value
        }
    }

    ; split \0
    got_str := StrGet(bufW, -nret_len, "UTF-16") ; includes \0
    start_idx := 1
    result_array := Array()
    loop nret_len {
        if Ord(SubStr(got_str, A_Index, 1)) == 0 {
            result_array.Push(SubStr(got_str, start_idx, A_Index - start_idx))
            start_idx := A_Index + 1
        }
    }
    return result_array
}
; --------------------------------------------------------------
; Struct Parsers
; --------------------------------------------------------------
class RawInputHidData {
    static RAWINPUTHEADER_SIZE := 8 + (A_PtrSize * 2)
    /** @param {Buffer} buf */
    __New(buf) {
        if Type(buf) !== "Buffer" {
            throw Error("unexpected param: buf")
        }
        this.buf := buf
        rawDataLen := buf.Size - RawInputHidData.RAWINPUTHEADER_SIZE - 8
        rawDataBuf := Buffer(rawDataLen, 0)
        DllCall("RtlMoveMemory", "Ptr", rawDataBuf.Ptr, "Ptr", buf.Ptr + RawInputHidData.RAWINPUTHEADER_SIZE + 8, "UPtr", rawDataLen)
        this.rawData := rawDataBuf
    }
    Header_dwType => NumGet(this.buf, 0, "UInt") ; ((RAWINPUT)buf).header.dwType: DWORD
    Header_dwSize => NumGet(this.buf, 4, "UInt")
    Header_hDevice => NumGet(this.buf, 8, "UPtr")
    Header_wParam => NumGet(this.buf, 8 + A_PtrSize, "UPtr")
    Data_dwSizeHid => NumGet(this.buf, RawInputHidData.RAWINPUTHEADER_SIZE, "UInt")
    Data_dwCount => NumGet(this.buf, RawInputHidData.RAWINPUTHEADER_SIZE + 4, "UInt")
    /** @type {Buffer} */
    Data_rawData => this.rawData
}
class CapsResult {
    /**
     * @param {Buffer} preparseddata 
     * @param {HidpButtonCapsArray} buttoncaps 
     * @param {HidpValueCapsArray} valuecaps
     * @param {ArraySortable} valid_Collection_indexes
     */
    __New(preparseddata, buttoncaps, valuecaps, valid_Collection_indexes) {
        this._preparseddata := preparseddata
        this._buttoncaps := buttoncaps
        this._valuecaps := valuecaps
        this._valid_Collection_indexes := valid_Collection_indexes
    }
    /** @type {Buffer} */
    PreparsedData => this._preparseddata
    /** @type {HidpButtonCapsArray} */
    ButtonCaps => this._buttoncaps
    /** @type {HidpValueCapsArray} */
    ValueCaps => this._valuecaps
    /** @type {ArraySortable} */
    ValidCollectionIndexes => this._valid_Collection_indexes
}
class HidpCaps {
    static STRUCT_LENGTH := 64
    /** @param {Buffer} buf */
    __New(buf) {
        if Type(buf) !== "Buffer" || buf.Size !== HidpCaps.STRUCT_LENGTH {
            throw Error("unexpected param: buf")
        }
        this.buf := buf
    }
    Usage                     => NumGet(this.buf, 0, "UShort")
    UsagePage                 => NumGet(this.buf, 2, "UShort")
    InputReportByteLength     => NumGet(this.buf, 4, "UShort")
    OutputReportByteLength    => NumGet(this.buf, 6, "UShort")
    FeatureReportByteLength   => NumGet(this.buf, 8, "UShort")
    ;Reserved[17][UShort]
    NumberLinkCollectionNodes => NumGet(this.buf, 44, "UShort")
    NumberInputButtonCaps     => NumGet(this.buf, 46, "UShort")
    NumberInputValueCaps      => NumGet(this.buf, 48, "UShort")
    NumberInputDataIndices    => NumGet(this.buf, 50, "UShort")
    NumberOutputButtonCaps    => NumGet(this.buf, 52, "UShort")
    NumberOutputValueCaps     => NumGet(this.buf, 54, "UShort")
    NumberOutputDataIndices   => NumGet(this.buf, 56, "UShort")
    NumberFeatureButtonCaps   => NumGet(this.buf, 58, "UShort")
    NumberFeatureValueCaps    => NumGet(this.buf, 60, "UShort")
    NumberFeatureDataIndices  => NumGet(this.buf, 62, "UShort")
}
class HidpButtonCaps {
    static STRUCT_LENGTH := 72
    /** @param {Buffer} buf */
    __New(buf) {
        if Type(buf) !== "Buffer" || buf.Size !== HidpButtonCaps.STRUCT_LENGTH {
            throw Error("unexpected param: buf")
        }
        this.buf := buf
    }
    UsagePage               => NumGet(this.buf, 0, "UShort") ; USAGE
    ReportID                => NumGet(this.buf, 2, "UChar") ; UCHAR
    IsAlias                 => NumGet(this.buf, 3, "UChar") ; BOOLEAN
    BitField                => NumGet(this.buf, 4, "UShort") ; USHORT
    LinkCollection          => NumGet(this.buf, 6, "UShort") ; USHORT
    LinkUsage               => NumGet(this.buf, 8, "UShort") ; USAGE
    LinkUsagePage           => NumGet(this.buf, 10, "UShort") ; USAGE
    IsRange                 => NumGet(this.buf, 12, "UChar") ; BOOLEAN
    IsStringRange           => NumGet(this.buf, 13, "UChar") ; BOOLEAN
    IsDesignatorRange       => NumGet(this.buf, 14, "UChar") ; BOOLEAN
    IsAbsolute              => NumGet(this.buf, 15, "UChar") ; BOOLEAN
    ReportCount             => NumGet(this.buf, 16, "UShort") ; USHORT
    ; Reserved2     ; pos: 18, [UShort] * 1   
    ; Reserved[9]   ; pos: 20, [UInt] * 9
    ; --- union Range
    RangeUsageMin           => NumGet(this.buf, 56, "UShort") ; USAGE
    RangeUsageMax           => NumGet(this.buf, 58, "UShort") ; USAGE
    RangeStringMin          => NumGet(this.buf, 60, "UShort") ; USHORT
    RangeStringMax          => NumGet(this.buf, 62, "UShort") ; USHORT
    RangeDesignatorMin      => NumGet(this.buf, 64, "UShort") ; USHORT
    RangeDesignatorMax      => NumGet(this.buf, 66, "UShort") ; USHORT
    RangeDataIndexMin       => NumGet(this.buf, 68, "UShort") ; USHORT
    RangeDataIndexMax       => NumGet(this.buf, 70, "UShort") ; USHORT
    ; --- union NotRange
    NotRangeUsage           => NumGet(this.buf, 56, "UShort") ; USAGE
    NotRangeReserved1       => NumGet(this.buf, 58, "UShort") ; USAGE
    NotRangeStringIndex     => NumGet(this.buf, 60, "UShort") ; USHORT
    NotRangeReserved2       => NumGet(this.buf, 62, "UShort") ; USHORT
    NotRangeDesignatorIndex => NumGet(this.buf, 64, "UShort") ; USHORT
    NotRangeReserved3       => NumGet(this.buf, 66, "UShort") ; USHORT
    NotRangeDataIndex       => NumGet(this.buf, 68, "UShort") ; USHORT
    NotRangeReserved4       => NumGet(this.buf, 70, "UShort") ; USHORT
}
class HidpValueCaps {
    static STRUCT_LENGTH := 72
    /** @param {Buffer} buf */
    __New(buf) {
        if Type(buf) !== "Buffer" || buf.Size !== HidpValueCaps.STRUCT_LENGTH {
            throw Error("unexpected param: buf")
        }
        this.buf := buf
    }
    UsagePage               => NumGet(this.buf, 0, "UShort") ; USAGE
    ReportID                => NumGet(this.buf, 2, "UChar") ; UCHAR
    IsAlias                 => NumGet(this.buf, 3, "UChar") ; BOOLEAN
    BitField                => NumGet(this.buf, 4, "UShort") ; USHORT
    LinkCollection          => NumGet(this.buf, 6, "UShort") ; USHORT
    LinkUsage               => NumGet(this.buf, 8, "UShort") ; USAGE
    LinkUsagePage           => NumGet(this.buf, 10, "UShort") ; USAGE
    IsRange                 => NumGet(this.buf, 12, "UChar") ; BOOLEAN
    IsStringRange           => NumGet(this.buf, 13, "UChar") ; BOOLEAN
    IsDesignatorRange       => NumGet(this.buf, 14, "UChar") ; BOOLEAN
    IsAbsolute              => NumGet(this.buf, 15, "UChar") ; BOOLEAN
    HasNull                 => NumGet(this.buf, 16, "UChar") ; BOOLEAN
    ; Reserved     ; pos: 17, [UChar] * 1   
    BitSize                 => NumGet(this.buf, 18, "UShort") ; USHORT
    ReportCount             => NumGet(this.buf, 20, "UShort") ; USHORT
    ; Reserved2[5] ; pos: 22, [UShort] * 5
    UnitsExp                => NumGet(this.buf, 32, "UInt") ; ULONG
    Units                   => NumGet(this.buf, 36, "UInt") ; ULONG
    LogicalMin              => NumGet(this.buf, 40, "Int") ; LONG
    LogicalMax              => NumGet(this.buf, 44, "Int") ; LONG
    PhysicalMin             => NumGet(this.buf, 48, "Int") ; LONG
    PhysicalMax             => NumGet(this.buf, 52, "Int") ; LONG
    ; --- union Range
    RangeUsageMin           => NumGet(this.buf, 56, "UShort") ; USAGE
    RangeUsageMax           => NumGet(this.buf, 58, "UShort") ; USAGE
    RangeStringMin          => NumGet(this.buf, 60, "UShort") ; USHORT
    RangeStringMax          => NumGet(this.buf, 62, "UShort") ; USHORT
    RangeDesignatorMin      => NumGet(this.buf, 64, "UShort") ; USHORT
    RangeDesignatorMax      => NumGet(this.buf, 66, "UShort") ; USHORT
    RangeDataIndexMin       => NumGet(this.buf, 68, "UShort") ; USHORT
    RangeDataIndexMax       => NumGet(this.buf, 70, "UShort") ; USHORT
    ; --- union NotRange
    NotRangeUsage           => NumGet(this.buf, 56, "UShort") ; USAGE
    NotRangeReserved1       => NumGet(this.buf, 58, "UShort") ; USAGE
    NotRangeStringIndex     => NumGet(this.buf, 60, "UShort") ; USHORT
    NotRangeReserved2       => NumGet(this.buf, 62, "UShort") ; USHORT
    NotRangeDesignatorIndex => NumGet(this.buf, 64, "UShort") ; USHORT
    NotRangeReserved3       => NumGet(this.buf, 66, "UShort") ; USHORT
    NotRangeDataIndex       => NumGet(this.buf, 68, "UShort") ; USHORT
    NotRangeReserved4       => NumGet(this.buf, 70, "UShort") ; USHORT
}
class CapsArrayBase {
    __New() {
        this.array_buf := Array()
    }
    __Item[index] {
        get {
            return this.array_buf[index]
        }
    }
    /** @type {Integer} */
    Length => this.array_buf.Length
    __Enum(n) {
        if n !== 1 {
            throw Error("only 1 value supported")
        }
        current_index := 1
        _enum(&Value1) {
            if current_index <= this.Length {
                Value1 := this[current_index]
                current_index += 1
                return true
            } else {
                return false
            }
        }
        return _enum
    }
}
class HidpButtonCapsArray extends CapsArrayBase {
    /** @param {Buffer} buf */
    __New(buf) {
        if Type(buf) !== "Buffer" || Mod(buf.Size, HidpButtonCaps.STRUCT_LENGTH) !== 0 {
            throw Error("unexpected param: buf")
        }
        super.__New()
        len := buf.Size // HidpButtonCaps.STRUCT_LENGTH
        this.array_buf.Length := len
        Loop len {
            item_buf := Buffer(HidpButtonCaps.STRUCT_LENGTH)
            DllCall("RtlMoveMemory", "Ptr", item_buf.Ptr, "Ptr", buf.Ptr + (A_Index - 1) * HidpButtonCaps.STRUCT_LENGTH, "UPtr", HidpButtonCaps.STRUCT_LENGTH) ; AutoHotKey index starts from 1
            this.array_buf[A_Index] := HidpButtonCaps(item_buf)
        }
    }
    /**
     * @param {Number} index 
     * @type {HidpButtonCaps}
     */
    __Item[index] {
        get {
            return this.array_buf[index]
        }
    }
}
class HidpValueCapsArray extends CapsArrayBase {
    /** @param {Buffer} buf */
    __New(buf) {
        if Type(buf) !== "Buffer" || Mod(buf.Size, HidpValueCaps.STRUCT_LENGTH) !== 0 {
            throw Error("unexpected param: buf")
        }
        super.__New()
        len := buf.Size // HidpValueCaps.STRUCT_LENGTH
        this.array_buf.Length := len
        Loop len {
            item_buf := Buffer(HidpValueCaps.STRUCT_LENGTH)
            DllCall("RtlMoveMemory", "Ptr", item_buf.Ptr, "Ptr", buf.Ptr + (A_Index - 1) * HidpValueCaps.STRUCT_LENGTH, "UPtr", HidpValueCaps.STRUCT_LENGTH) ; AutoHotKey index starts from 1
            this.array_buf[A_Index] := HidpValueCaps(item_buf)
        }
    }
    /**
     * @param {Number} index 
     * @type {HidpValueCaps}
     */
    __Item[index] {
        get {
            return this.array_buf[index]
        }
    }
}
class ArraySortable extends Array {
    Sort(Callback := unset) {
        DefaultCallback(First, Second) {
            if First == Second {
                return 0
            } else if First > Second {
                return 1
            } else {
                return -1
            }
        }
        current_callback := Callback ?? DefaultCallback
        ; bubble sort
        Loop (this.Length - 1) { ; 1-start
            last_index := this.Length - A_Index
            Loop last_index {
                first := this[A_Index]
                second := this[A_Index + 1]
                if current_callback(first, second) > 0 {
                    this[A_Index] := second
                    this[A_Index + 1] := first
                }
            }
        }
    }
    Sorted(Callback := unset) {
        tmp := this.Clone()
        if IsSet(Callback) {
            tmp.Sort(Callback)
        } else {
            tmp.Sort()
        }
        return tmp
    }
}
