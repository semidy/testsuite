require "cdr"

have_error = false

function check_error(a)
	if have_error then
		a:dump_full_log()
		print("core show locks output:")
		print(a:cli("core show locks"))
		error()
	end
end

function print_error(err)
	print(err)
	have_error = true
end

function sipp_exec(scenario, name, host)
	local inf = "data.csv"
	return proc.exec_io("sipp",
	"127.0.0.1",
	"-m", "1",
	"-sf", scenario,
	"-inf", "sipp/" .. inf,
	"-infindex", inf, "0",
	"-i", host,
	"-p", 5060,
	"-timeout", "60",
	"-timeout_error",
	"-set", "user", name,
	"-set", "file", inf,
	"-trace_err"
	)
end

function sipp_exec_and_wait(scenario, name, local_port)
	return sipp_check_error(sipp_exec(scenario, name, local_port), scenario)
end

function sipp_check_error(p, scenario)
	local res, err = p:wait()

	if not res then
		print_error(err)
		return res, err
	end
	if res ~= 0 then
		print_error("error while executing " .. scenario .. " sipp scenario (sipp exited with status " .. res .. ")\n" .. p.stderr:read("*a"))
	end

	return res, err
end

function check_cdr_accountcode(a, record, accountcode)
	local c = check("error parsing cdr file", cdr.new(a))

	fail_if(not c[record], string.format("expected accountcode '%s' in record %s, but file only has %s record(s)", accountcode, record, c:len()))
	fail_if(c[record]["accountcode"] ~= accountcode, string.format("expected accountcode '%s' in record %s, but found '%s'", accountcode, record, tostring(c[record]["accountcode"])))
end

-- This function will execute the three sipp scenarios using the inf file
-- provided.  This will cause index[3] to dial either index[2] or index[1] and
-- then transfer the called party to which ever index was not called
-- originally.  Whether index[2] or index[1] is called depends on the index[3],
-- see the sipp/data.csv file to determine who is called in which situations.
function do_transfer_and_check_results(accountcode, index)
	local a = ast.new()
	a:load_config("configs/ast1/sip.conf")
	a:load_config("configs/ast1/extensions.conf")
	a:spawn()

	-- register our three peers
	sipp_exec_and_wait("sipp/register.xml", index[1], "127.0.0.2")
	sipp_exec_and_wait("sipp/register.xml", index[2], "127.0.0.3")
	sipp_exec_and_wait("sipp/register.xml", index[3], "127.0.0.4")

	-- make the calls and transfers
	local t1 = sipp_exec("sipp/wait-for-call.xml", index[1], "127.0.0.2")
	local t2 = sipp_exec("sipp/wait-for-call-do-hangup.xml", index[2], "127.0.0.3")
	local t3 = sipp_exec("sipp/call-then-blind-transfer.xml", index[3], "127.0.0.4")

	-- wait for everything to finish
	sipp_check_error(t3, "sipp/call-then-blind-transfer.xml")
	sipp_check_error(t2, "sipp/wait-for-call-do-hangup.xml")
	sipp_check_error(t1, "sipp/wait-for-call.xml")

	check_error(a)
	proc.perror(a:term_or_kill())

	-- examine the CDR records generated to make sure account code is present
	check_cdr_accountcode(a, 2, accountcode)
end

-- test dialing a peer without an account code set.  The resulting account code
-- should be that of the dialing peer
print("Calling test2 from test3 and transferring to test1")
do_transfer_and_check_results("account3", {"test1", "test2", "test3"})

-- now test dialing a peer with an account code set.  The resulting account
-- code should be that of the dialing peer
print("Calling test3 from test1 and transferring to test2")
do_transfer_and_check_results("account1", {"test3", "test2", "test1"})
