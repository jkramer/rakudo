role Perl6::Metamodel::BUILDPLAN {
    has @!BUILDALLPLAN;
    has @!BUILDPLAN;
    
    # Creates the plan for building up the object. This works
    # out what we'll need to do up front, so we can just zip
    # through the "todo list" each time we need to make an object.
    # The plan is an array of code objects / arrays. If the element
    # is a code object, it should be called as a method without any
    # further parameters.  If it is an array, then the first element
    # of each array is an "op" # representing the task to perform:
    #   code = call as method (for BUILD or TWEAK)
    #   0 class name attr_name = try to find initialization value
    #   1 class attr_name code = call default value closure if needed
    #   2 class name attr_name = set a native int attribute
    #   3 class name attr_name = set a native num attribute
    #   4 class name attr_name = set a native str attribute
    #   5 class attr_name code = call default value closure if needed, int attr
    #   6 class attr_name code = call default value closure if needed, num attr
    #   7 class attr_name code = call default value closure if needed, str attr
    #   8 die if a required attribute is not present
    #   9 class attr_name code = run attribute container initializer
    #   10 class attr_name = touch/vivify attribute if part of mixin
    method create_BUILDPLAN($obj) {
        # First, we'll create the build plan for just this class.
        my @plan;
        my @attrs := $obj.HOW.attributes($obj, :local(1));

        # Emit any container initializers. Also build hash of attrs we
        # do not touch in any of the BUILDPLAN so we can spit out vivify
        # ops at the end.
        my %attrs_untouched;
        for @attrs {
            if nqp::can($_, 'container_initializer') {
                my $ci := $_.container_initializer;
                if nqp::isconcrete($ci) {
                    nqp::push(@plan,[9, $obj, $_.name, $ci]);
                    next;
                }
            }
            if nqp::objprimspec($_.type) == 0 {
                %attrs_untouched{$_.name} := NQPMu;
            }
        }
        
        # Does it have its own BUILD?
        my $build := $obj.HOW.find_method($obj, 'BUILD', :no_fallback(1));
        if !nqp::isnull($build) && $build {
            # We'll call the custom one.
            nqp::push(@plan,$build);
        }
        else {
            # No custom BUILD. Rather than having an actual BUILD
            # in Mu, we produce ops here per attribute that may
            # need initializing.
            for @attrs {
                if $_.has_accessor {
                    my $attr_name := $_.name;
                    my $name      := nqp::substr($attr_name, 2);
                    my $typespec  := nqp::objprimspec($_.type);
                    if $typespec {
                        nqp::push(@plan,[nqp::add_i(1, $typespec),
                                              $obj, $name, $attr_name]);
                    } else {
                        nqp::push(@plan,[0, $obj, $name, $attr_name]);
                    }
                }
            }
        }

        # Ensure that any required attributes are set
        for @attrs {
            if nqp::can($_, 'required') && $_.required {
                nqp::push(@plan,[8, $obj, $_.name, $_.required]);
                nqp::deletekey(%attrs_untouched, $_.name);
            }
        }

        # Check if there's any default values to put in place.
        for @attrs {
            if nqp::can($_, 'build') {
                my $default := $_.build;
                if !nqp::isnull($default) && $default {
                    my $typespec := nqp::objprimspec($_.type);
                    if $typespec {
                        nqp::push(@plan,[nqp::add_i(4, $typespec), $obj, $_.name, $default]);
                    }
                    else {
                        nqp::push(@plan,[1, $obj, $_.name, $default]);
                    }
                    nqp::deletekey(%attrs_untouched, $_.name);
                }
            }
        }

        # Add vivify instructions.
        for %attrs_untouched {
            nqp::push(@plan,[10, $obj, $_.key]);
        }

        # Does it have a TWEAK?
        my $TWEAK := $obj.HOW.find_method($obj, 'TWEAK', :no_fallback(1));
        if !nqp::isnull($TWEAK) && $TWEAK {
            nqp::push(@plan,$TWEAK);
        }

        # Install plan for this class.
        @!BUILDPLAN := @plan;

        # Now create the full plan by getting the MRO, and working from
        # least derived to most derived, copying the plans.
        my @all_plan;
        my @mro := self.mro($obj);
        my $i := +@mro;
        my $noops := 0;
        while $i > 0 {
            $i := $i - 1;
            my $class := @mro[$i];
            for $class.HOW.BUILDPLAN($class) {
                if nqp::islist($_) && $_[0] == 10 {   # noop in BUILDALLPLAN
                    $noops := 1;
                }
                else {
                    nqp::push(@all_plan, $_);
                }
            }
        }

        # if same number of elems and no noops, identical, so just keep 1 copy
        @!BUILDALLPLAN := $noops || +@all_plan != +@plan ?? @all_plan !! @plan;
    }
    
    method BUILDPLAN($obj) {
        @!BUILDPLAN
    }
    
    method BUILDALLPLAN($obj) {
        @!BUILDALLPLAN
    }
}
