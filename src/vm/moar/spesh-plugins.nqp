## Method plugins
## Only used when the name is a constant at the use site!

# Private method resolution can be specialized based on invocant type. This is
# used for speeding up resolution of private method calls in roles; those in
# classes can be resolved by static optimization.
nqp::speshreg('perl6', 'privmeth', -> $obj, str $name {
    nqp::speshguardtype($obj, $obj.WHAT);
    $obj.HOW.find_private_method($obj, $name)
});

# A resolution like `self.Foo::bar()` can have the resolution specialized. We
# fall back to the dispatch:<::> if there is an exception that'd need to be
# thrown.
nqp::speshreg('perl6', 'qualmeth', -> $obj, str $name, $type {
    nqp::speshguardtype($obj, $obj.WHAT);
    if nqp::istype($obj, $type) {
        # Resolve to the correct qualified method.
        nqp::speshguardtype($type, $type.WHAT);
        $obj.HOW.find_method_qualified($obj, $type, $name)
    }
    else {
        # We'll throw an exception; return a thunk that will delegate to the
        # slow path implementation to do the throwing.
        -> $inv, *@pos, *%named {
            $inv.'dispatch:<::>'($name, $type, |@pos, |%named)
        }
    }
});

# A call like `$obj.?foo` is probably worth specializing via the plugin. In
# some cases, it will be code written to be generic that only hits one type
# of invocant under a given use case, so we can handle it via deopt. Even if
# there are a few different invocant types, the table lookup from the guard
# structure is still likely faster than the type lookup. (In the future, we
# should consider an upper limit on table size for the really polymorphic
# things).
sub discard-and-nil(*@pos, *%named) { Nil }
nqp::speshreg('perl6', 'maybemeth', -> $obj, str $name {
    nqp::speshguardtype($obj, $obj.WHAT);
    my $meth := nqp::tryfindmethod($obj, $name);
    nqp::isconcrete($meth)
        ?? $meth
        !! &discard-and-nil
});
