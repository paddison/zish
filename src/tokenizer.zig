const std = @import("std");

//*************************************************************************************************
//* Implementation
//*************************************************************************************************

/// Types of tokens.
const TokenType = enum {
    word,
    pipe,
    less,
    greater,
    greater_greater,
    greater_ampersand,
    greater_greater_ampersand,
    ampersand,
    end,
};

/// Special characters which are reserved and cannot be contained in a word.
const special_characters = [_]u8{ '|', '<', '>', '&', ' ', '\n', '\r' };

/// States of the tokenizer
const States = enum {
    start,
    greater,
    greater_greater,
    word,
};

/// A single token.
/// Contains the type of it, and the position of where it is in the buffer.
const Token = struct {
    t_type: TokenType,
    start: usize,
    end: usize,
};

/// Tokenizes an input.
/// Has to be initialized with a buffer.
/// New tokens can be obtained with a call to next().
/// The tokenizer is done, once it returns the TokenType.end token.
pub const Tokenizer = struct {
    index: usize,
    buf: [:0]const u8,

    const Self = @This();

    /// Initialize with a new command buffer.
    pub fn init(buf: [:0]const u8) Self {
        return Self{
            .index = 0,
            .buf = buf,
        };
    }

    /// Returns the next token.
    /// The last token that will be returned is the 'end' token.
    pub fn next(self: *Self) Token {
        var token = Token{
            .t_type = undefined,
            .start = self.index,
            .end = undefined,
        };
        state: switch (States.start) {
            .start => switch (self.buf[self.index]) {
                0 => {
                    token.t_type = .end;
                },
                '|' => {
                    self.index += 1;
                    token.t_type = .pipe;
                },
                '<' => {
                    self.index += 1;
                    token.t_type = .less;
                },
                '&' => {
                    self.index += 1;
                    token.t_type = .ampersand;
                },
                '>' => {
                    self.index += 1;
                    continue :state .greater;
                },
                ' ', '\t' => {
                    self.index += 1;
                    token.start = self.index;
                    continue :state .start;
                },
                '\n', '\r' => {
                    // treat new line as if it were a 0 byte character.
                    token.t_type = .end;
                },
                else => {
                    // all other characters are words
                    self.index += 1;
                    continue :state .word;
                },
            },
            .greater => switch (self.buf[self.index]) {
                '>' => {
                    self.index += 1;
                    continue :state .greater_greater;
                },
                '&' => {
                    self.index += 1;
                    token.t_type = .greater_ampersand;
                },
                else => token.t_type = .greater,
            },
            .greater_greater => switch (self.buf[self.index]) {
                '&' => {
                    self.index += 1;
                    token.t_type = .greater_greater_ampersand;
                },
                else => token.t_type = .greater_greater,
            },
            .word => switch (self.buf[self.index]) {
                '&', '|', '<', '>', ' ', '\t', '\n', '\r', 0 => token.t_type = .word,
                else => {
                    self.index += 1;
                    continue :state .word;
                },
            },
        }

        token.end = self.index;

        return token;
    }
};

//*************************************************************************************************
//* Tests
//*************************************************************************************************

const assert = std.debug.assert;

fn compare_token(expected_tokens: []const []const u8, expected_types: []const TokenType, buf: [:0]const u8) void {
    var tk = Tokenizer.init(buf);
    for (expected_tokens, expected_types) |token, typ| {
        const next: Token = tk.next();
        assert(std.mem.eql(u8, token, buf[next.start..next.end]));
        assert(typ == next.t_type);
    }

    assert(tk.next().t_type == .end);
}

test "test every token is recognized" {
    const expected_tokens = [_][:0]const u8{ "ls", "-al", "<", "|", ">", "&", ">>", ">&", ">>&" };
    const expected_types = [_]TokenType{ .word, .word, .less, .pipe, .greater, .ampersand, .greater_greater, .greater_ampersand, .greater_greater_ampersand };
    for (expected_tokens, expected_types) |token, typ| {
        compare_token(&.{token}, &.{typ}, token);
    }
}

test "test empty string is end token" {
    const line: [:0]const u8 = "";
    var tk = Tokenizer.init(line);
    assert(tk.next().t_type == TokenType.end);
}

test "test only spaces is end token" {
    const line: [:0]const u8 = "             ";
    var tk = Tokenizer.init(line);
    assert(tk.next().t_type == TokenType.end);
}

test "test only spaces and newline is null" {
    const line: [:0]const u8 = "   \n";
    var tk = Tokenizer.init(line);
    assert(tk.next().t_type == TokenType.end);
}

test "test newline ends token stream" {
    const line: [:0]const u8 = "ls -al\n   hiding";
    const expected_tokens = [_][]const u8{ "ls", "-al" };
    const expected_types = [_]TokenType{ .word, .word };

    compare_token(&expected_tokens, &expected_types, line);
}

test "test simple command" {
    const line: [:0]const u8 = "ls -al | grep *.txt >> out >>&";
    const expected_tokens = [_][]const u8{ "ls", "-al", "|", "grep", "*.txt", ">>", "out", ">>&" };
    const expected_types = [_]TokenType{ .word, .word, .pipe, .word, .word, .greater_greater, .word, .greater_greater_ampersand };

    compare_token(&expected_tokens, &expected_types, line);
}
