//! Lexer: source text to tokens with line numbers.

#[derive(Clone, Debug, PartialEq)]
pub enum Tok {
    Name(String),
    Str(Vec<u8>),
    Int(i64),
    /// A keyword or an operator.
    Sym(&'static str),
    Eof,
}

const KEYWORDS: &[&str] = &[
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local", "nil",
    "not", "or", "repeat", "return", "then", "true", "until", "while",
];

/// Longest first, so "..." wins over ".." over ".".
const OPS: &[&str] = &[
    "...", "..", "//", "==", "~=", "<=", ">=", "<<", ">>", "::", "+", "-", "*", "/", "%", "^", "#", "&", "~", "|", "<",
    ">", "=", "(", ")", "{", "}", "[", "]", ";", ":", ",", ".",
];

pub fn tokenize(src: &[u8]) -> Result<Vec<(Tok, u32)>, (u32, String)> {
    let mut lx = Lexer { s: src, i: 0, line: 1 };
    let mut out = Vec::new();
    loop {
        lx.skip_space()?;
        let line = lx.line;
        let t = lx.token()?;
        let eof = t == Tok::Eof;
        out.push((t, line));
        if eof {
            return Ok(out);
        }
    }
}

struct Lexer<'a> {
    s: &'a [u8],
    i: usize,
    line: u32,
}

type R<T> = Result<T, (u32, String)>;

impl Lexer<'_> {
    fn peek(&self, k: usize) -> u8 {
        self.s.get(self.i + k).copied().unwrap_or(0)
    }

    fn err<T>(&self, msg: impl Into<String>) -> R<T> {
        Err((self.line, msg.into()))
    }

    /// Consumes a newline sequence (\n, \r, \r\n, \n\r) at the cursor.
    fn newline(&mut self) {
        let c = self.peek(0);
        self.i += 1;
        let d = self.peek(0);
        if (d == b'\n' || d == b'\r') && d != c {
            self.i += 1;
        }
        self.line += 1;
    }

    fn skip_space(&mut self) -> R<()> {
        loop {
            match self.peek(0) {
                b'\n' | b'\r' => self.newline(),
                b' ' | b'\t' | 0x0b | 0x0c => self.i += 1,
                b'-' if self.peek(1) == b'-' => {
                    self.i += 2;
                    if self.peek(0) == b'[' {
                        if let Some(level) = self.long_open() {
                            self.long_body(level, "comment")?;
                            continue;
                        }
                    }
                    while self.i < self.s.len() && !matches!(self.peek(0), b'\n' | b'\r') {
                        self.i += 1;
                    }
                }
                _ => return Ok(()),
            }
        }
    }

    /// At '[': if this opens a long bracket ([[ or [==[), consumes it and returns its level.
    fn long_open(&mut self) -> Option<usize> {
        let mut j = 1;
        while self.peek(j) == b'=' {
            j += 1;
        }
        if self.peek(j) == b'[' {
            self.i += j + 1;
            Some(j - 1)
        } else {
            None
        }
    }

    fn long_body(&mut self, level: usize, what: &str) -> R<Vec<u8>> {
        let start_line = self.line;
        let mut out = Vec::new();
        if matches!(self.peek(0), b'\n' | b'\r') {
            self.newline();
        }
        loop {
            if self.i >= self.s.len() {
                return Err((start_line, format!("unfinished long {what}")));
            }
            let c = self.peek(0);
            if c == b']' {
                let mut j = 1;
                while self.peek(j) == b'=' {
                    j += 1;
                }
                if j - 1 == level && self.peek(j) == b']' {
                    self.i += j + 1;
                    return Ok(out);
                }
                out.push(c);
                self.i += 1;
            } else if c == b'\n' || c == b'\r' {
                self.newline();
                out.push(b'\n');
            } else {
                out.push(c);
                self.i += 1;
            }
        }
    }

    fn token(&mut self) -> R<Tok> {
        let c = self.peek(0);
        if self.i >= self.s.len() {
            return Ok(Tok::Eof);
        }
        if c.is_ascii_alphabetic() || c == b'_' {
            let st = self.i;
            while self.peek(0).is_ascii_alphanumeric() || self.peek(0) == b'_' {
                self.i += 1;
            }
            let w = std::str::from_utf8(&self.s[st..self.i]).unwrap_or("");
            return Ok(match KEYWORDS.iter().find(|k| **k == w) {
                Some(k) => Tok::Sym(k),
                None => Tok::Name(w.to_string()),
            });
        }
        if c.is_ascii_digit() || (c == b'.' && self.peek(1).is_ascii_digit()) {
            return self.number();
        }
        if c == b'"' || c == b'\'' {
            return self.string(c);
        }
        if c == b'[' {
            if let Some(level) = self.long_open() {
                return Ok(Tok::Str(self.long_body(level, "string")?));
            }
        }
        for op in OPS {
            if self.s[self.i..].starts_with(op.as_bytes()) {
                self.i += op.len();
                return Ok(Tok::Sym(op));
            }
        }
        if c.is_ascii_graphic() {
            self.err(format!("unexpected symbol '{}'", c as char))
        } else {
            self.err(format!("unexpected byte 0x{c:02x}"))
        }
    }

    fn number(&mut self) -> R<Tok> {
        let st = self.i;
        let hex = self.peek(0) == b'0' && matches!(self.peek(1), b'x' | b'X');
        if hex {
            self.i += 2;
        }
        while self.peek(0).is_ascii_alphanumeric() || self.peek(0) == b'_' || (self.peek(0) == b'.' && self.peek(1) != b'.') {
            self.i += 1;
        }
        let text = String::from_utf8_lossy(&self.s[st..self.i]).into_owned();
        let digits = if hex { &text[2..] } else { &text[..] };
        let radix = if hex { 16 } else { 10 };
        if !digits.is_empty() && digits.chars().all(|ch| ch.is_digit(radix)) {
            return match i64::from_str_radix(digits, radix) {
                Ok(n) => Ok(Tok::Int(n)),
                Err(_) => self.err(format!("integer literal '{text}' is out of range")),
            };
        }
        let floaty = text.contains('.') || (!hex && text.contains(['e', 'E'])) || (hex && text.contains(['p', 'P']));
        if floaty && text.chars().all(|ch| ch.is_ascii_hexdigit() || ".eEpPxX+-".contains(ch)) {
            self.err(format!("floating-point numbers are not supported: '{text}' (integers only)"))
        } else {
            self.err(format!("malformed number near '{text}'"))
        }
    }

    fn string(&mut self, quote: u8) -> R<Tok> {
        self.i += 1;
        let mut out = Vec::new();
        loop {
            let c = self.peek(0);
            if self.i >= self.s.len() || c == b'\n' || c == b'\r' {
                return self.err("unfinished string");
            }
            self.i += 1;
            if c == quote {
                return Ok(Tok::Str(out));
            }
            if c != b'\\' {
                out.push(c);
                continue;
            }
            let e = self.peek(0);
            self.i += 1;
            match e {
                b'n' => out.push(b'\n'),
                b't' => out.push(b'\t'),
                b'r' => out.push(b'\r'),
                b'a' => out.push(7),
                b'b' => out.push(8),
                b'f' => out.push(12),
                b'v' => out.push(11),
                b'\\' => out.push(b'\\'),
                b'"' => out.push(b'"'),
                b'\'' => out.push(b'\''),
                b'\n' | b'\r' => {
                    self.i -= 1;
                    self.newline();
                    out.push(b'\n');
                }
                b'z' => loop {
                    match self.peek(0) {
                        b'\n' | b'\r' => self.newline(),
                        b' ' | b'\t' | 0x0b | 0x0c => self.i += 1,
                        _ => break,
                    }
                },
                b'x' => {
                    let h = |c: u8| (c as char).to_digit(16);
                    match (h(self.peek(0)), h(self.peek(1))) {
                        (Some(a), Some(b)) => {
                            out.push((a * 16 + b) as u8);
                            self.i += 2;
                        }
                        _ => return self.err("hexadecimal digit expected in '\\x' escape"),
                    }
                }
                b'0'..=b'9' => {
                    let mut n = (e - b'0') as u32;
                    for _ in 0..2 {
                        if !self.peek(0).is_ascii_digit() {
                            break;
                        }
                        n = n * 10 + (self.peek(0) - b'0') as u32;
                        self.i += 1;
                    }
                    if n > 255 {
                        return self.err("decimal escape too large");
                    }
                    out.push(n as u8);
                }
                b'u' => {
                    if self.peek(0) != b'{' {
                        return self.err("missing '{' in '\\u{xxxx}'");
                    }
                    self.i += 1;
                    let mut n: u32 = 0;
                    let mut any = false;
                    while let Some(d) = (self.peek(0) as char).to_digit(16) {
                        n = n.saturating_mul(16).saturating_add(d);
                        self.i += 1;
                        any = true;
                    }
                    if !any || self.peek(0) != b'}' {
                        return self.err("malformed '\\u{xxxx}' escape");
                    }
                    self.i += 1;
                    match char::from_u32(n) {
                        Some(ch) => out.extend_from_slice(ch.encode_utf8(&mut [0; 4]).as_bytes()),
                        None => return self.err("UTF-8 value too large or invalid in '\\u' escape"),
                    }
                }
                _ => return self.err("invalid escape sequence"),
            }
        }
    }
}
