mod common;
use common::*;

#[test]
fn basics() {
    assert_eq!(ok("return 1 + 2, 'a' .. 'b', 7 // 2, 2 * 3 - 1"), "3, ab, 3, 5");
    assert_eq!(ok("return 1 .. 2, 'x' .. 10, -3 .. ''"), "12, x10, -3");
    assert_eq!(ok("return nil, true, false, not nil, not 0"), "nil, true, false, true, false");
    assert_eq!(ok("return 1 == 1, 'a' == 'a', {} == {}, 1 == '1', 1 ~= 2"), "true, true, false, false, true");
    assert_eq!(ok("return 1 < 2, 2 <= 2, 'a' < 'b', 'b' >= 'a', 'Z' < 'a'"), "true, true, true, true, true");
    assert_eq!(ok("return nil and 1, false or 2, 1 and 2, nil or false, 0 and 'zero'"), "nil, 2, 2, false, zero");
    assert_eq!(ok("return #'abc', #{1, 2, 3}, #{}, #{n = 1}"), "3, 3, 0, 0");
    assert_eq!(ok("return 0x10, 0XfF, -0x1"), "16, 255, -1");
    assert_eq!(ok("return 2 + 3 * 4, (2 + 3) * 4, 2 .. 3 + 4, -2 * -2, not 1 == 2"), "14, 20, 27, 4, false");
    assert_eq!(ok("return 1 .. 2 .. 3, 'a' .. 'b' .. 'c' == 'abc'"), "123, true");
    assert_eq!(ok("return math.maxinteger, math.mininteger"), "9223372036854775807, -9223372036854775808");
}

#[test]
fn integer_division_and_modulo_follow_lua() {
    assert_eq!(ok("return 7 // 2, -7 // 2, 7 // -2, -7 // -2, 6 // 3, -6 // 3"), "3, -4, -4, 3, 2, -2");
    assert_eq!(ok("return 7 % 3, -7 % 3, 7 % -3, -7 % -3, 6 % 3, -6 % 3, 0 % 5"), "1, 2, -2, -1, 0, 0, 0");
    assert_eq!(ok("return math.mininteger % -1, math.mininteger // 1"), "0, -9223372036854775808");
    assert!(err("return math.mininteger // -1").contains("integer overflow in '//'"));
    assert!(err("return 1 // 0").contains("attempt to perform 'n//0'"));
    assert!(err("return 1 % 0").contains("attempt to perform 'n%%0'"));
}

#[test]
fn overflow_is_an_error() {
    assert!(err("return math.maxinteger + 1").contains("integer overflow in '+'"));
    assert!(err("return math.mininteger - 1").contains("integer overflow in '-'"));
    assert!(err("return math.maxinteger * 2").contains("integer overflow in '*'"));
    assert!(err("return -math.mininteger").contains("integer overflow in unary '-'"));
    assert!(err("return math.abs(math.mininteger)").contains("overflow"));
    assert!(err("return 9223372036854775808").contains("out of range"));
}

#[test]
fn no_string_number_coercion() {
    assert!(err("local s = '10' return s + 1").contains("attempt to perform arithmetic on a string value (local 's')"));
    assert!(err("return 1 < '2'").contains("attempt to compare number with string"));
    assert!(err("return {} < {}").contains("attempt to compare two table values"));
}

#[test]
fn closures_and_upvalues() {
    let counter = "
        local function counter()
          local n = 0
          return function() n = n + 1 return n end
        end
        local a, b = counter(), counter()
        a() a()
        return a(), b()";
    assert_eq!(ok(counter), "3, 1");
    // Two closures share one upvalue.
    let shared = "
        local function pair()
          local v = 0
          local function get() return v end
          local function set(x) v = x end
          return get, set
        end
        local get, set = pair()
        set(42)
        local get2, set2 = pair()
        set2(7)
        return get(), get2()";
    assert_eq!(ok(shared), "42, 7");
    // Each loop iteration has a fresh variable.
    let loops = "
        local fs = {}
        for i = 1, 3 do fs[i] = function() return i end end
        local gs = {}
        for _, v in ipairs({10, 20}) do gs[#gs + 1] = function() return v end end
        local hs = {}
        local j = 0
        while j < 2 do j = j + 1 local k = j * 100 hs[j] = function() return k end end
        return fs[1](), fs[2](), fs[3](), gs[1](), gs[2](), hs[1](), hs[2]()";
    assert_eq!(ok(loops), "1, 2, 3, 10, 20, 100, 200");
    // Upvalues several levels up; captured parameters.
    let deep = "
        local function a(x)
          return function(y)
            return function(z) x = x + 1 return x + y + z end
          end
        end
        local f = a(1)(10)
        return f(100), f(100)";
    assert_eq!(ok(deep), "112, 113");
    // A closure sees later assignments to the captured local.
    assert_eq!(ok("local x = 1 local f = function() return x end x = 5 return f()"), "5");
    // Recursive local function.
    assert_eq!(ok("local function fact(n) if n <= 1 then return 1 end return n * fact(n - 1) end return fact(20)"), "2432902008176640000");
    // Shadowing.
    assert_eq!(ok("local x = 1 do local x = 2 end local x = x + 10 return x"), "11");
}

#[test]
fn varargs() {
    assert_eq!(ok("local function f(...) return select('#', ...) end return f(), f(nil), f(1, nil, nil)"), "0, 1, 3");
    assert_eq!(ok("local function f(...) return select(2, ...) end return f(1, 2, 3)"), "2, 3");
    assert_eq!(ok("local function f(...) return select(-1, ...) end return f(1, 2, 3)"), "3");
    assert_eq!(ok("local function f(...) local t = {...} return #t, t[2] end return f(5, 6, 7)"), "3, 6");
    assert_eq!(ok("local function f(a, ...) return a, ... end return f(1, 2, 3)"), "1, 2, 3");
    assert_eq!(ok("local function f(...) return ..., 'end' end return f(1, 2)"), "1, end");
    assert_eq!(ok("local function f(...) return (...) end return f(1, 2)"), "1");
    assert_eq!(ok("local function g() return 1, 2, 3 end local function f(...) return ... end return f(g())"), "1, 2, 3");
    assert_eq!(ok("local function f(...) local a, b = ... return a, b end return f(9)"), "9, nil");
    assert!(err("return select(0, 1)").contains("bad argument #1 to 'select'"));
    assert!(compile("x.lua", "local function f() return ... end").is_err());
    // The main chunk is vararg (no arguments).
    assert_eq!(ok("return select('#', ...)"), "0");
}

#[test]
fn multiple_returns_and_assignment() {
    assert_eq!(ok("local function f() return 1, 2 end local a, b, c = f() return a, b, c"), "1, 2, nil");
    assert_eq!(ok("local function f() return 1, 2 end local a, b, c = f(), 10 return a, b, c"), "1, 10, nil");
    assert_eq!(ok("local function f() return 1, 2 end local t = {f(), f()} return #t"), "3");
    assert_eq!(ok("local function f() return 1, 2 end local t = {(f())} return #t"), "1");
    assert_eq!(ok("local a, b = 1 return a, b"), "1, nil");
    assert_eq!(ok("local a, b = 1, 2, 3 return a, b"), "1, 2");
    assert_eq!(ok("local a, b = 1, 2 a, b = b, a return a, b"), "2, 1");
    // Targets (table and key) are evaluated before the values; stores go left to right.
    assert_eq!(ok("local t = {} local i = 1 i, t[i] = i + 1, 20 return i, t[1], t[2]"), "2, 20, nil");
    assert_eq!(ok("local t = {} t.x, t.x = 1, 2 return t.x"), "2");
    assert_eq!(ok("local function f() end local a = f() return a"), "nil");
    assert_eq!(ok("local function f() return end return select('#', f())"), "0");
}

#[test]
fn numeric_for() {
    let collect = |h: &str| ok(&format!("local t = {{}} for i = {h} do t[#t + 1] = i end return table.concat(t, ' ')"));
    assert_eq!(collect("1, 3"), "1 2 3");
    assert_eq!(collect("1, 0"), "");
    assert_eq!(collect("10, 1, -3"), "10 7 4 1");
    assert_eq!(collect("1, 10, 4"), "1 5 9");
    assert_eq!(collect("-2, 2"), "-2 -1 0 1 2");
    assert_eq!(collect("5, 5"), "5");
    assert_eq!(collect("5, 5, -1"), "5");
    assert_eq!(collect("math.maxinteger - 1, math.maxinteger"), "9223372036854775806 9223372036854775807");
    assert_eq!(collect("math.mininteger, math.mininteger + 2"), "-9223372036854775808 -9223372036854775807 -9223372036854775806");
    assert_eq!(collect("math.maxinteger, math.maxinteger - 1, -1"), "9223372036854775807 9223372036854775806");
    assert_eq!(collect("1, math.maxinteger, math.maxinteger"), "1");
    // Changing the loop variable does not change the loop.
    assert_eq!(ok("local n = 0 for i = 1, 3 do i = i * 10 n = n + i end return n"), "60");
    assert!(err("for i = 1, 2, 0 do end").contains("'for' step is zero"));
    assert!(err("for i = 1, 'x' do end").contains("'for' limit value must be a number"));
}

#[test]
fn breaks() {
    let src = "
        local out = {}
        for i = 1, 3 do
          for j = 1, 3 do
            if j == 2 then break end
            out[#out + 1] = i .. j
          end
          if i == 2 then break end
        end
        local k = 0
        while true do
          k = k + 1
          repeat
            if k > 1 then break end
            out[#out + 1] = 'r' .. k
          until true
          if k == 3 then break end
        end
        for _, v in ipairs({1, 2, 3}) do if v == 2 then break end out[#out + 1] = 'g' .. v end
        return table.concat(out, ' '), k";
    assert_eq!(ok(src), "11 21 r1 g1, 3");
    assert!(compile("x.lua", "break").is_err());
    assert!(compile("x.lua", "for i = 1, 2 do local f = function() break end end").is_err());
}

#[test]
fn while_repeat_if() {
    assert_eq!(ok("local i, s = 0, 0 while i < 10 do i = i + 1 s = s + i end return s"), "55");
    assert_eq!(ok("local i = 0 repeat local j = i i = i + 1 until j >= 3 return i"), "4");
    let f = "local function f(x) if x < 0 then return 'neg' elseif x == 0 then return 'zero' elseif x < 10 then return 'small' else return 'big' end end";
    assert_eq!(ok(&format!("{f} return f(-1), f(0), f(5), f(50)")), "neg, zero, small, big");
}

#[test]
fn strings_and_escapes() {
    assert_eq!(ok(r#"return "\65\066\x43\u{48}\z
                       I""#), "ABCHI");
    assert_eq!(ok(r#"return #"a\nb\tc\\d\"e\'f", 'it\'s'"#), "11, it's");
    assert_eq!(ok(r"return '\0' == '\x00', #'\0\0'"), "true, 2");
    assert_eq!(ok("return \"line\\\nnext\""), "line\nnext");
    assert_eq!(ok("return [[\nfirst\nsecond]]"), "first\nsecond");
    assert_eq!(ok("return [==[a]]b]=]c]==]"), "a]]b]=]c");
    assert_eq!(ok("return [[]]"), "");
    assert_eq!(ok("-- comment\nreturn --[[ inline ]] 1 --[==[ long\ncomment ]==] + 1"), "2");
    assert_eq!(ok("return '\\u{44f}'"), "я");
    assert!(compile("x.lua", "return 'abc").is_err());
    assert!(compile("x.lua", "return '\\q'").is_err());
    assert!(compile("x.lua", "return [[abc").is_err());
    assert!(compile("x.lua", "return '\\300'").is_err());
}

#[test]
fn tables() {
    assert_eq!(ok("local t = {1, 2, x = 3, ['y'] = 4, [10] = 5} return t[1], t[2], t.x, t.y, t[10], #t"), "1, 2, 3, 4, 5, 2");
    assert_eq!(ok("local t = {} t[1] = 'a' t[2] = 'b' t[2] = nil return #t, t[2]"), "1, nil");
    assert_eq!(ok("local t = {{x = 1}} t[1].x = t[1].x + 1 return t[1].x"), "2");
    assert_eq!(ok("local t = {true, false} return t[1], t[2], t[3]"), "true, false, nil");
    assert_eq!(ok("local t = {} t[true] = 1 t[t] = 2 return t[true], t[t]"), "1, 2");
    assert_eq!(ok("local t = {1, nil, 3} return t[3]"), "3");
    assert!(err("local t = {} t[nil] = 1").contains("table index is nil"));
    assert!(err("local t = nil return t.x").contains("attempt to index a nil value (local 't')"));
    assert!(err("local t = {} return t.a.b").contains("attempt to index a nil value (field 'a')"));
    assert_eq!(ok("local t = {} return t[nil]"), "nil");
}

#[test]
fn methods() {
    let src = "
        local obj = {n = 0}
        function obj:add(k) self.n = self.n + k return self end
        function obj.get(self) return self.n end
        obj:add(2):add(3)
        return obj:get(), obj.get(obj)";
    assert_eq!(ok(src), "5, 5");
    assert_eq!(ok("local s = 'abc' return s:upper(), ('x'):rep(3), s:len(), s.len(s)"), "ABC, xxx, 3, 3");
    assert!(err("local t = {} t:nope()").contains("attempt to call a nil value (method 'nope')"));
}

#[test]
fn pairs_iterate_in_insertion_order() {
    let src = "
        local t = {}
        t.z = 1 t.a = 2 t[10] = 3 t[1] = 4 t.m = 5
        local ks = {}
        for k, v in pairs(t) do ks[#ks + 1] = tostring(k) .. '=' .. v end
        return table.concat(ks, ' ')";
    assert_eq!(ok(src), "z=1 a=2 10=3 1=4 m=5");
    // Constructor order, removals and re-insertions.
    let src = "
        local t = {x = 1, 'p', y = 2, 'q'}
        t.x = nil
        t.x = 9
        t.w = 0
        local ks = {}
        for k in pairs(t) do ks[#ks + 1] = tostring(k) end
        return table.concat(ks, ' ')";
    assert_eq!(ok(src), "1 y 2 x w");
    // Clearing fields during the traversal is allowed.
    let src = "
        local t = {}
        for i = 1, 100 do t['k' .. i] = i end
        local n = 0
        for k, v in pairs(t) do t[k] = nil n = n + v end
        return n, next(t)";
    assert_eq!(ok(src), "5050, nil");
    // next by hand.
    assert_eq!(ok("local t = {a = 1, b = 2} local k, v = next(t) local k2 = next(t, k) return k, v, k2, next(t, k2)"), "a, 1, b, nil");
    assert!(err("local t = {a = 1} return next(t, 'zz')").contains("invalid key to 'next'"));
    // Many insertions and deletions (tombstone compaction) keep the order.
    let src = "
        local t = {}
        for i = 1, 1000 do t[i] = i end
        for i = 1, 990 do t[i] = nil end
        for i = 2000, 2002 do t[i] = i end
        local ks = {}
        for k in pairs(t) do ks[#ks + 1] = k end
        return table.concat(ks, ' ')";
    assert_eq!(ok(src), "991 992 993 994 995 996 997 998 999 1000 2000 2001 2002");
}

#[test]
fn determinism_across_vms_and_clones() {
    let src = "
        local t = {}
        for i = 1, 200 do t['key' .. (i * 7919 % 1000)] = i end
        t[{}] = 1
        local out = {}
        for k, v in pairs(t) do out[#out + 1] = type(k) == 'string' and k or 'table' end
        return table.concat(out, ',')";
    let a = ok(src);
    for _ in 0..5 {
        assert_eq!(ok(src), a);
    }
    // A cloned VM continues identically and independently.
    let mut h = host();
    let chunk = compile("m.lua", "local n = 0 return { inc = function() n = n + 1 return n end }").unwrap();
    load(&mut h, "m", &chunk).unwrap();
    call_path(&mut h, "m", &["inc"], &[]).unwrap();
    let mut h2 = T { vm: h.vm.clone(), log: Vec::new() };
    assert_eq!(call_path(&mut h, "m", &["inc"], &[]).unwrap(), vec![Value::Int(2)]);
    assert_eq!(call_path(&mut h, "m", &["inc"], &[]).unwrap(), vec![Value::Int(3)]);
    assert_eq!(call_path(&mut h2, "m", &["inc"], &[]).unwrap(), vec![Value::Int(2)]);
}

#[test]
fn base_library() {
    assert_eq!(ok("return type(nil), type(1), type('s'), type({}), type(print_), type(type)".replace("print_", "nil").as_str()), "nil, number, string, table, nil, function");
    assert_eq!(ok("return tostring(12), tostring(nil), tostring(true), tostring('x')"), "12, nil, true, x");
    assert_eq!(ok("return tonumber('42'), tonumber(' -7 '), tonumber('0x1F'), tonumber('1.5'), tonumber('abc'), tonumber(5)"), "42, -7, 31, nil, nil, 5");
    assert_eq!(ok("return tonumber('ff', 16), tonumber('z', 36), tonumber('102', 2), tonumber('99999999999999999999')"), "255, 35, nil, nil");
    assert_eq!(ok("return tonumber('1e3'), tonumber(''), tonumber('-'), tonumber({})"), "nil, nil, nil, nil");
    assert_eq!(ok("return assert(1, 'm', 3)"), "1, m, 3");
    assert!(err("assert(false)").contains("assertion failed!"));
    assert_eq!(err("assert(nil, 'custom')"), "custom");
    assert_eq!(ok("local t = {} for i, v in ipairs({5, 6, nil, 8}) do t[#t + 1] = i .. ':' .. v end return table.concat(t, ' ')"), "1:5 2:6");
    assert!(err("for k in pairs(nil) do end").contains("bad argument #1 to 'pairs' (table expected, got nil)"));
    assert!(err("return type()").contains("bad argument #1 to 'type'"));
}

#[test]
fn errors_and_pcall() {
    assert_eq!(ok("return pcall(function() return 1, 2 end)"), "true, 1, 2");
    assert_eq!(ok("return pcall(error, 'boom', 0)"), "false, boom");
    assert_eq!(ok("local ok, e = pcall(function()\n error('boom')\n end) return ok, e"), "false, test.lua:2: boom");
    assert_eq!(ok("local ok, e = pcall(function() local x = nil return x.y end) return e"), "test.lua:1: attempt to index a nil value (local 'x')");
    assert_eq!(ok("local ok, e = pcall(error, {code = 7}) return type(e), e.code"), "table, 7");
    assert_eq!(ok("local ok, e = pcall(error) return ok, e"), "false, nil");
    assert_eq!(ok("return pcall(nil)"), "false, test.lua:1: attempt to call a nil value");
    // Level 2 blames the caller.
    let src = "local function check(x)\n if not x then error('bad x', 2) end\n end\n local ok, e = pcall(function()\n check(false)\n end)\n return e";
    assert_eq!(ok(src), "test.lua:5: bad x");
    // Nested pcall and recovery.
    assert_eq!(ok("local ok = pcall(function() pcall(error, 'x') error('y') end) return ok, 1 + 1"), "false, 2");
    // Errors keep working after pcall (stack restored).
    assert_eq!(ok("for i = 1, 100 do pcall(function(...) error('x') end, 1, 2, 3) end local t = {1, 2, 3} return #t"), "3");
}

#[test]
fn error_messages_have_lines_and_traceback() {
    let src = "local cards = {}\nfunction cards.spell(g)\n  return g.damge(1)\nend\nlocal function run()\n  return cards.spell({})\nend\nreturn run()";
    let e = run(src).unwrap_err();
    assert_eq!(e.kind(), ErrorKind::Runtime);
    assert_eq!(e.message, "test.lua:3: attempt to call a nil value (field 'damge')");
    let tb = e.traceback.join("\n");
    assert!(tb.contains("test.lua:3: in function 'cards.spell'"), "{tb}");
    assert!(tb.contains("test.lua:6: in function 'run'"), "{tb}");
    assert!(e.to_string().contains("stack traceback:"));
    assert_eq!(err("local a = 1\nlocal b\nreturn a + b"), "test.lua:3: attempt to perform arithmetic on a nil value (local 'b')");
    assert_eq!(err("local t = {}\nreturn t.x .. 'a'"), "test.lua:2: attempt to concatenate a nil value (field 'x')");
    assert_eq!(err("return #nil"), "test.lua:1: attempt to get length of a nil value");
    assert_eq!(err("local s = 'x'\nreturn s.y.z"), "test.lua:2: attempt to index a nil value (field 'y')");
    assert_eq!(err("return table.insert(1, 2)"), "test.lua:1: bad argument #1 to 'table.insert' (table expected, got number)");
    assert_eq!(err("\n\nerror('top')"), "test.lua:3: top");
    // Syntax errors.
    let e = compile("cards.lua", "local x = 1\nif x then\n  x = 2\n").unwrap_err();
    assert_eq!(e.kind(), ErrorKind::Compile);
    assert_eq!(e.message, "cards.lua:4: 'end' expected (to close 'if' at line 2) near '<eof>'");
    let e = compile("cards.lua", "local x = = 1").unwrap_err();
    assert_eq!(e.message, "cards.lua:1: unexpected symbol near '='");
    let e = compile("cards.lua", "x = 1").unwrap_err();
    assert_eq!(e.message, "cards.lua:1: assignment to undeclared global 'x' (declare it with 'local')");
}

#[test]
fn table_library() {
    assert_eq!(ok("local t = {1, 2, 3} table.insert(t, 4) table.insert(t, 1, 0) return table.concat(t, ',')"), "0,1,2,3,4");
    assert_eq!(ok("local t = {1, 2, 3} local v = table.remove(t) local w = table.remove(t, 1) return v, w, table.concat(t, ',')"), "3, 1, 2");
    assert_eq!(ok("local t = {} return table.remove(t), #t"), "nil, 0");
    assert!(err("local t = {1} table.insert(t, 5, 1)").contains("position out of bounds"));
    assert!(err("table.insert({}, 1, 2, 3)").contains("wrong number of arguments to 'insert'"));
    assert_eq!(ok("local t = {5, 2, 8, 1} table.sort(t) return table.concat(t, ',')"), "1,2,5,8");
    assert_eq!(ok("local t = {'b', 'c', 'a'} table.sort(t, function(a, b) return a > b end) return table.concat(t)"), "cba");
    // Stable with a comparator.
    let src = "
        local t = {{k = 2, n = 'a'}, {k = 1, n = 'b'}, {k = 2, n = 'c'}, {k = 1, n = 'd'}, {k = 2, n = 'e'}}
        table.sort(t, function(x, y) return x.k < y.k end)
        local o = {} for _, v in ipairs(t) do o[#o + 1] = v.n end return table.concat(o)";
    assert_eq!(ok(src), "bdace");
    // An inconsistent comparator is not a crash.
    assert_eq!(ok("local t = {3, 1, 2, 5, 4} table.sort(t, function() return true end) return #t"), "5");
    assert!(err("local t = {1, 'a'} table.sort(t)").contains("attempt to compare"));
    assert_eq!(ok("return table.unpack({1, 2, 3})"), "1, 2, 3");
    assert_eq!(ok("return table.unpack({1, 2, 3}, 2)"), "2, 3");
    assert_eq!(ok("return table.unpack({1, 2, 3}, 2, 4)"), "2, 3, nil");
    assert_eq!(ok("return select('#', table.unpack({}))"), "0");
    assert!(err("return table.unpack({}, 1, 1000000)").contains("too many results"));
    assert_eq!(ok("return table.concat({1, 'a', 2}), table.concat({}, ','), table.concat({1, 2, 3}, '-', 2, 3)"), "1a2, , 2-3");
    assert!(err("return table.concat({1, {}, 3})").contains("invalid value (at index 2) in table for 'concat'"));
}

#[test]
fn string_library() {
    assert_eq!(ok("local s = 'hello' return s:sub(2, 3), s:sub(-3), s:sub(2), s:sub(0), s:sub(10), s:sub(-100, 2), s:sub(3, 2)"), "el, llo, ello, hello, , he, ");
    assert_eq!(ok("return ('ab'):rep(3), ('ab'):rep(3, ','), ('x'):rep(0), ('x'):rep(-1)"), "ababab, ab,ab,ab, , ");
    assert_eq!(ok("return string.format('%d damage to %s (%d%%)', 4, 'all', 100)"), "4 damage to all (100%)");
    assert_eq!(ok("return string.format('%s %s %s', nil, true, {} ~= nil)"), "nil true true");
    assert!(err("return string.format('%f', 1)").contains("invalid conversion '%f'"));
    assert!(err("return string.format('%d')").contains("bad argument #2 to 'string.format' (no value)"));
    assert!(err("return string.format('%d', 'x')").contains("bad argument #2 to 'string.format' (number expected, got string)"));
    assert_eq!(ok("return ('hello world'):find('o w'), ('hello'):find('l', 1, true), ('hello'):find('z'), ('abc'):find('')"), "5, 3, nil, 1, 0");
    assert_eq!(ok("return ('a.b'):find('.', 1, true), ('hello'):find('l', 4), ('hello'):find('l', -1)"), "2, 4, nil");
    assert!(err("return ('a.b'):find('.')").contains("patterns are not supported"));
    assert_eq!(ok("return ('ABC'):byte(), ('ABC'):byte(2, 3), ('ABC'):byte(-1), string.char(72, 105)"), "65, 66, 67, Hi");
    assert!(err("return string.char(256)").contains("value out of range"));
    assert_eq!(ok("return ('MiXeD'):upper(), ('MiXeD'):lower(), ('abc'):len(), #''"), "MIXED, mixed, 3, 0");
}

#[test]
fn math_library() {
    assert_eq!(ok("return math.min(3, 1, 2), math.max(3, 1, 2), math.abs(-5), math.abs(5), math.clamp(15, 0, 10), math.clamp(-1, 0, 10), math.floor(7)"), "1, 3, 5, 5, 10, 0, 7");
    assert!(err("return math.min()").contains("bad argument #1 to 'math.min'"));
    assert!(err("return math.clamp(1, 5, 2)").contains("min is greater than max"));
    assert_eq!(ok("return math.huge, math.pi, math.random"), "nil, nil, nil");
}

#[test]
fn list_library() {
    let pre = "local t = {5, 1, 4, 2, 3} ";
    assert_eq!(ok(&format!("{pre} return table.concat(list.filter(t, function(x) return x > 2 end), ',')")), "5,4,3");
    assert_eq!(ok(&format!("{pre} return table.concat(list.map(t, function(x, i) return x * i end), ',')")), "5,2,12,8,15");
    assert_eq!(ok(&format!("{pre} return table.concat(list.map(t, function(x) if x > 3 then return x end end), ',')")), "5,4");
    assert_eq!(ok(&format!("{pre} return list.count(t, function(x) return x % 2 == 1 end), list.count(t)")), "3, 5");
    assert_eq!(ok(&format!("{pre} return list.any(t, function(x) return x > 4 end), list.all(t, function(x) return x > 1 end)")), "true, false");
    assert_eq!(ok(&format!("{pre} return list.sum(t), list.sum(t, function(x) return x * 10 end), list.sum({{}})")), "15, 150, 0");
    let src = "local ms = {{n = 'a', atk = 3}, {n = 'b', atk = 1}, {n = 'c', atk = 3}, {n = 'd', atk = 2}}
        local s = list.sort_by(ms, function(m) return -m.atk end)
        local o = {} for _, m in ipairs(s) do o[#o + 1] = m.n end return table.concat(o), ms[1].n";
    assert_eq!(ok(src), "acdb, a");
    assert!(err("return list.sum({1, 'x'})").contains("list.sum: item 2 is a string"));
    assert_eq!(ok("return list.shuffle, list.random"), "nil, nil");
}

#[test]
fn function_names_in_tracebacks() {
    let src = "local M = {sub = {}}\nlocal f = function() error('x') end\nM.sub.g = function() f() end\nlocal t = {h = function() M.sub.g() end}\nt.h()";
    let e = run(src).unwrap_err();
    let tb = e.traceback.join("\n");
    for want in ["test.lua:2: in function 'f'", "test.lua:3: in function 'M.sub.g'", "test.lua:4: in function 'h'"] {
        assert!(tb.contains(want), "{want} not in:\n{tb}");
    }
    let e = run("local x\nlocal y = 1 + (function() error('z') end)()").unwrap_err();
    assert!(e.traceback.join("\n").contains("in function '<anonymous:2>'"), "{:?}", e.traceback);
}

#[test]
fn readding_a_key_moves_it_to_the_end() {
    let src = "
        local t = {a = 1, b = 2, c = 3}
        t.a = nil t.a = 10 t.b = 20
        for i = 1, 50 do t.c = nil t.c = i end
        local ks = {} for k, v in pairs(t) do ks[#ks + 1] = k .. v end
        return table.concat(ks, ' ')";
    assert_eq!(ok(src), "b20 a10 c50");
}

#[test]
fn library_edges_near_integer_limits() {
    assert_eq!(ok("local t = {[math.maxinteger - 1] = 'a', [math.maxinteger] = 'b'} return table.concat(t, '-', math.maxinteger - 1, math.maxinteger)"), "a-b");
    assert_eq!(ok("local t = {[math.maxinteger] = 'x'} return table.unpack(t, math.maxinteger, math.maxinteger)"), "x");
    assert_eq!(ok("return select(math.mininteger + 1 > 0 and 1 or 1, 'a')"), "a");
    assert!(err("return select(math.mininteger, 'a')").contains("index out of range"));
    assert_eq!(ok("return ('abc'):sub(math.mininteger, math.maxinteger), ('abc'):byte(math.maxinteger), ('abc'):find('c', math.mininteger)"), "abc, nil, 3, 3");
    assert_eq!(ok("local n = 0 for i, v in ipairs({[math.maxinteger] = 1}) do n = n + 1 end return n"), "0");
    assert!(err("return table.remove({}, math.mininteger)").contains("position out of bounds"));
    assert!(err("return table.insert({}, math.maxinteger, 1)").contains("position out of bounds"));
    assert_eq!(ok("local t, k = {}, 1 for i = 0, 61 do t[k] = i k = k * 2 end return #t >= 1"), "true");
}
