# Fixture for the test that a test item's globals are released once it finishes.
#
# The two items are in one file and in this order, because `run_tests` iterates
# files in `Dict` order but test items within a file in source order.
#
# The probes are parked in `Main` rather than in the item's own module precisely
# because `Main` is what the teardown does not touch.

@testitem "memory probe: bind" begin
    leaked = zeros(UInt8, 8_000_000)
    Core.eval(Main, :(TESTITEMRUNNER_MEMORY_PROBE = $(WeakRef(leaked))))
    @test length(leaked) == 8_000_000

    # A `const` cannot be released from Julia 1.12 on, so this probe pins the limitation
    # the docstring of `release_module_globals!` describes. If Julia ever makes it
    # collectable again this test fails, which is the reminder to update that docstring
    # and the user docs.
    const pinned = zeros(UInt8, 8_000_000)
    Core.eval(Main, :(TESTITEMRUNNER_MEMORY_PROBE_CONST = $(WeakRef(pinned))))
    @test length(pinned) == 8_000_000

    # A type annotated global rejects `nothing`, so the teardown falls back to an empty
    # array of the same type. Typed globals are Julia 1.8 and later, and this file is
    # parsed on every version the package supports, so the declaration is built at run
    # time rather than written out.
    #
    # Everything about this probe stays inside the `let`: reading the value back out here
    # would leave it in a slot of the item's own top level scope, which keeps it alive
    # whatever the teardown does. `invokelatest` because the binding is too new for the
    # world this statement was compiled in.
    if VERSION >= v"1.8"
        let
            Core.eval(@__MODULE__, Meta.parse("typed::Vector{UInt8} = zeros(UInt8, 8_000_000)"))

            value = Base.invokelatest(getfield, @__MODULE__, :typed)
            @test length(value) == 8_000_000

            Core.eval(Main, :(TESTITEMRUNNER_MEMORY_PROBE_TYPED = $(WeakRef(value))))
        end
    else
        # Nothing to release, and `nothing` is always reachable, so the check item's
        # assertion holds trivially
        Core.eval(Main, :(TESTITEMRUNNER_MEMORY_PROBE_TYPED = $(WeakRef(nothing))))
        @test true
    end
end

@testitem "memory probe: check" begin
    GC.gc(true)
    GC.gc(true)

    @test isdefined(Main, :TESTITEMRUNNER_MEMORY_PROBE)
    @test Main.TESTITEMRUNNER_MEMORY_PROBE.value === nothing

    # Released through the empty-array fallback
    @test Main.TESTITEMRUNNER_MEMORY_PROBE_TYPED.value === nothing

    # See the note in the item above. Before Julia 1.12 whether a `const` can be
    # reassigned depends on the value, so there is nothing stable to assert there.
    if VERSION < v"1.12"
        @test true
    else
        @test Main.TESTITEMRUNNER_MEMORY_PROBE_CONST.value !== nothing
    end
end
