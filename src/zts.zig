const std = @import("std");

const Mode = enum {
    find_directive,
    reading_directive_name,
    content_line,
};

fn Template(comptime path: []const u8) type {
    @setEvalBranchQuota(500000);
    comptime var str = @embedFile(path);
    comptime var decls = &[_]std.builtin.Type.Declaration{};

    // empty strings, or strings that dont start with a .directive - just map the whole string to .all and return early
    if (str.len < 1 or str[0] != '.') {
        // @compileLog("file is not a template");
        comptime var fields: [1]std.builtin.Type.StructField = undefined;

        fields[0] = .{
            .name = "all",
            .type = *const [str.len:0]u8,
            .is_comptime = true,
            .alignment = 0,
            .default_value = str,
        };
        // @compileLog("non-template using fields", fields);
        return @Type(.{
            .Struct = .{
                .layout = .Auto,
                .fields = &fields,
                .decls = decls,
                .is_tuple = false,
            },
        });
    }

    // PASS 1 - just count up the number of directives, so we can create the fields array of known size
    var mode: Mode = .find_directive;
    var num_fields = 0;
    for (str) |c| {
        switch (mode) {
            .find_directive => {
                switch (c) {
                    '.' => mode = .reading_directive_name,
                    ' ', '\n' => {},
                    else => mode = .content_line,
                }
            },
            .reading_directive_name => {
                switch (c) {
                    '\n' => {
                        // got the end of a directive !
                        num_fields += 1;
                        mode = .find_directive;
                    },
                    ' ', '\t', '.', '-', '{', '}', '[', ']', ':' => mode = .content_line,
                    else => {},
                }
            },
            .content_line => {
                switch (c) {
                    '\n' => mode = .find_directive,
                    else => {},
                }
            },
        }
    }

    // @compileLog("num_fields =", num_fields);
    if (num_fields < 1) {
        @compileError("No fields found");
    }

    // now we know how many fields there should be, so is safe to statically define the fields array
    comptime var fields: [num_fields + 1]std.builtin.Type.StructField = undefined;

    // inject the all values first
    fields[0] = .{
        .name = "all",
        .type = [str.len]u8,
        .is_comptime = true,
        .alignment = 0,
        .default_value = str[0..],
    };

    var directive_start = 0;
    var maybe_directive_start = 0;
    var content_start = 0;
    var field_num = 1;

    // PASS 2
    // this is a bit more involved, as we cant allocate, and we want to do this in 1 single sweep of the data.
    // Scan through the data again, looking for a directive, and keep track of the offset of the start of content.
    // It uses 2 vars - maybe_directive_start is used when it thinks there might be a new directive, which
    // reverts back to the last good directive_start when it is detected that its a false reading
    // When the next directive is seen, then the content block in the previous field needs to be truncated
    mode = .find_directive;
    for (str, 0..) |c, index| {
        // @compileLog(c, index);
        switch (mode) {
            .find_directive => {
                switch (c) {
                    '.' => {
                        maybe_directive_start = index;
                        mode = .reading_directive_name;
                        // @compileLog("maybe new directive at", maybe_directive_start);
                    },
                    ' ', '\t', '\n' => {}, // eat whitespace
                    else => mode = .content_line,
                }
            },
            .reading_directive_name => {
                switch (c) {
                    '\n' => {
                        // found a new directive - we need to patch the value of the previous content then
                        directive_start = maybe_directive_start;
                        if (field_num > 1) {
                            // @compileLog("patching", field_num - 1, content_start, directive_start - 1);
                            var adjusted_len = directive_start - content_start;
                            fields[field_num - 1].type = [adjusted_len]u8;
                            fields[field_num - 1].default_value = str[content_start .. directive_start - 1];
                            // @compileLog("patched previous to", fields[field_num - 1]);
                        }
                        const dname = str[directive_start + 1 .. index];
                        const dlen = str.len - index;
                        content_start = index + 1;
                        // got the end of a directive !
                        fields[field_num] = .{
                            .name = dname,
                            .type = [dlen]u8,
                            .is_comptime = true,
                            .alignment = 0,
                            .default_value = str[content_start..],
                        };
                        // @compileLog("field", field_num, fields[field_num]);
                        field_num += 1;
                        mode = .content_line;
                    },
                    ' ', '\t', '.', '-', '{', '}', '[', ']', ':' => { // invalid chars for directive name
                        mode = .content_line;
                        maybe_directive_start = directive_start;
                    },
                    else => {},
                }
            },
            .content_line => { // just eat the rest of the line till the next CR
                switch (c) {
                    '\n' => mode = .find_directive,
                    else => {},
                }
            },
        }
    }

    // @compileLog("fields", fields);

    return @Type(.{
        .Struct = .{
            .layout = .Auto,
            .fields = &fields,
            .decls = decls,
            .is_tuple = false,
        },
    });
}

test "hacky hack 1" {
    var out = std.io.getStdErr().writer();
    try out.writeAll("\n------------------hacky hack 1----------------------\n");

    const Thing = struct {
        comptime name: *const [10:0]u8 = "Name: {s}\n",
        comptime address: *const [10:0]u8 = "Addr: {s}\n",
    };

    inline for (@typeInfo(Thing).Struct.fields, 0..) |f, i| {
        try out.print("Thing field={} name={s} type={} is_comptime={} default_value={?}\n", .{ i, f.name, f.type, f.is_comptime, f.default_value });
    }

    var thing = Thing{};
    try out.print("typeof thing.name is {}\n", .{@TypeOf(thing.name)});
    try out.print(thing.name, .{"Rupert Montgomery"});
    try out.print(thing.address, .{"21 Main Street"});
}

fn HackyHack() type {
    comptime var fields: [2]std.builtin.Type.StructField = undefined;
    comptime var decls = &[_]std.builtin.Type.Declaration{};
    fields[0] = .{
        .name = "name",
        .type = *const [10:0]u8,
        .is_comptime = true,
        .alignment = 0,
        .default_value = "Name: {s}\n",
    };
    fields[1] = .{
        .name = "address",
        .type = *const [10:0]u8,
        .is_comptime = true,
        .alignment = 0,
        .default_value = "Addr: {s}\n",
    };
    return @Type(.{
        .Struct = .{
            .layout = .Auto,
            .fields = &fields,
            .decls = decls,
            .is_tuple = false,
        },
    });
}

test "hacky hack 2" {
    var out = std.io.getStdErr().writer();
    try out.writeAll("\n------------------hacky hack 2----------------------\n");

    comptime var Thing = HackyHack();

    inline for (@typeInfo(Thing).Struct.fields, 0..) |f, i| {
        try out.print("Thing field={} name={s} type={} is_comptime={} default_value={?}\n", .{ i, f.name, f.type, f.is_comptime, f.default_value });
    }

    comptime var thing = Thing{};
    try out.print("typeof thing.name is {}\n", .{@TypeOf(thing.name)});
    try out.writeAll("The lines below will crash without throwing an error ... so commented out\n");
    // try out.print(thing.name, .{"Rupert Montgomery"});
    // try out.print(thing.address, .{"21 Main Street"});
    try out.print("But I can do this still with no probs {s}\n", .{thing.name});
}

test "all" {
    var out = std.io.getStdErr().writer();
    try out.writeAll("\n------------------all.txt----------------------\n");
    const t = Template("testdata/all.txt");
    inline for (@typeInfo(t).Struct.fields, 0..) |f, i| {
        try out.print("all.txt field={} name={s} type={} is_comptime={} default_value={?}\n", .{ i, f.name, f.type, f.is_comptime, f.default_value });
    }
    comptime var data = Template("testdata/all.txt"){};
    try out.print("typeof data.all is {}\n", .{@TypeOf(data.all)});
    try out.print(data.all, .{});
    try out.print("value data.all is:\n{s}\n", .{data.all});
    try std.testing.expectEqual(57, data.all.len);
}

test "foobar" {
    var out = std.io.getStdErr().writer();
    const t = Template("testdata/foobar.txt");
    inline for (@typeInfo(t).Struct.fields, 0..) |f, i| {
        std.debug.print("foobar.txt has field {} name {s} type {}'\n", .{ i, f.name, f.type });
    }
    const data = t{};

    try out.print("Whole contents of foobar.txt is:\n---------------\n{s}\n---------------\n", .{data.all});
    try out.print("\nfoo: '{s}'\n", .{data.foo});
    try out.print("\nbar: '{s}'\n", .{data.bar});
    try std.testing.expectEqual(52, data.all.len);
    try std.testing.expectEqual(19, data.foo.len);
    try std.testing.expectEqual(24, data.bar.len);
}

test "edge-phantom-directive" {
    var out = std.io.getStdErr().writer();
    const t = Template("testdata/edge-phantom-directive.txt");

    inline for (@typeInfo(t).Struct.fields, 0..) |f, i| {
        try out.print("type has field {} name {s} type {}\n", .{ i, f.name, f.type });
    }

    const data = t{};
    try std.testing.expectEqual(49, data.header.len);
    try std.testing.expectEqual(179, data.body.len);
    try std.testing.expectEqual(185, data.footer.len);
    try std.testing.expectEqual(63, data.nested_footer.len);
    try out.print("You can see that the body has lots of phantom directives that didnt trick the parser:\n{s}\n", .{data.body});
    try out.print("\nAnd the footer as well:\n{s}\n", .{data.footer});
}

test "customer_details" {
    // create some test data to push through the HTML report
    const Invoice = struct {
        date: []const u8,
        details: []const u8,
        amount: u64,
    };

    const Customer = struct {
        name: []const u8,
        address: []const u8,
        credit: u64,
        invoices: []const Invoice,
    };

    const cust = Customer{
        .name = "Bill Smith",
        .address = "21 Main Street",
        .credit = 12345,
        .invoices = &[_]Invoice{
            .{ .date = "12 Sep 2023", .details = "New Hoodie", .amount = 9900 },
            .{ .date = "24 Sep 2023", .details = "2 Hotdogs with Cheese and Sauce", .amount = 1100 },
            .{ .date = "14 Oct 2023", .details = "Milkshake", .amount = 30 },
        },
    };
    _ = cust;

    var out = std.io.getStdErr().writer();
    const html_t = Template("testdata/customer_details.html");

    inline for (@typeInfo(html_t).Struct.fields, 0..) |f, i| {
        try out.print("html has field {} name {s} type {}\n", .{ i, f.name, f.type });
    }

    const html = html_t{};

    // do some basic tests on this loaded template
    // these are all fine
    try std.testing.expectEqual(517, html.all.len);

    try out.writeAll("------ details template -------\n");
    try out.print("{s}", .{html.details});
    try std.testing.expectEqual(126, html.details.len);
    try out.writeAll("------ invoice_table template -------\n");
    try out.print("{s}", .{html.invoice_table});
    try std.testing.expectEqual(119, html.invoice_table.len);
    try out.writeAll("------ invoice_row template -------\n");
    try out.print("{s}", .{html.invoice_row});
    try std.testing.expectEqual(109, html.invoice_row.len);
    try out.writeAll("------ invoice_row total -------\n");
    try out.print("{s}", .{html.invoice_total});
    try std.testing.expectEqual(112, html.invoice_total.len);
    try out.writeAll("\n-------------------------------\n");

    // IRL, should be able to use this template and the provided data like this to generate
    // a populated HTML page out of the segments

    // try out.print(&html.details, .{
    //     .name = cust.name,
    //     .address = cust.address,
    //     .credit = cust.credit,
    // });

    // try out.writeAll(&html.invoice_table_start);
    // var total: f32 = 0;

    // for (cust.invoices) |invoice| {
    //     try out.print(&html.invoice_row, invoice);
    //     total += invoice.amount;
    // }

    // try out.print(&html.invoice_table_total, .{ .total = total });
}
