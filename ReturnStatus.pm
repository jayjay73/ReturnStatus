# vim: set foldmethod=marker:
#
# Perl module to easily handle return values
# Copyright (c) 2015-2020 Jan Jaeger
# License: MIT License as found here: https://opensource.org/licenses/MIT
# The low down: You may copy this. You may use this as you see fit.
# You have to include this notice. I am not liable.
#
#

package ReturnStatus;

use strict;
use warnings;
use Moose;
with 'Throwable';
use Scalar::Util qw/reftype/;

use Data::Dumper;
use Carp qw(carp croak cluck);

use Exporter qw(import);
our @EXPORT_OK = qw(new success error conditional);

use overload '""' => \&stringify;
sub stringify {
    my $self= shift;

    #warn caller(0);
    #warn caller(1);
    #my $caller= caller;
    #warn $caller;
    my $ret_str;
    my $message= $self->{message};
    if (chomp $message) {
        #warn "chomped";
        my $lineend= (caller eq 'Throwable' or caller eq 'Template::Exception') ? "\n" : "";
        $ret_str= join (' ', $self->code, $message) . $lineend;
    } else {
        #warn "no chomp";
        my $lineend= (caller eq 'Throwable' or caller eq 'Template::Exception') ? " at $self->{_filename2} line $self->{_line2}\n" : "";
        $ret_str= join (' ', $self->code, $message, "[in $self->{_caller2}(), at or above $self->{_filename}:$self->{_line}]") . $lineend;
    }
    return $ret_str;
}

sub new {
    my $type= shift;
    my ($arg)= @_;
    #warn Dumper($arg);

    my $code;
    my $message;
    my $is_error;


    #my $mypackage= (caller(0))[0];
    # package name of the callee (this sub)
    my ($mypackage)= split '::', (caller(0))[3];
    #warn "caller 0: ", caller(0);
    #warn "caller 1: ", caller(1);
    #warn "caller 2: ", caller(2);
    #warn "caller 3: ", caller(3);
    #warn "caller 4: ", caller(4);

    if ( ((caller(1))[3] eq 'Throwable::throw') && (ref($arg) eq $mypackage) ) {
        #warn "mypackage: $mypackage";
        return $arg;
    }

    if (defined reftype $arg && (reftype $arg eq reftype {}) ) {
        $code= $arg->{code};
        $message= $arg->{message};
        $is_error= $arg->{is_error};
    } else {
        ($is_error, $code, $message)= @_;
    }

    my ($package, $filename, $line, $caller, $hasargs, $wantarray) = caller(1);
    my ($package2, $filename2, $line2, $caller2, $hasargs2, $wantarray2) = caller(2);

    my $err= {
        is_error => $is_error,
        code => $code,
        message => $message,
        _package=> $package,
        _filename=> $filename,
        _line=> $line,
        _caller=> $caller,

        _package2=> $package2,
        _filename2=> $filename2,
        _line2=> $line2,
        _caller2=> $caller2
    };
    return bless $err, $type;
}

sub ret {
    my $self= shift;
    my ($retval)= @_;

    my ($package, $filename, $line, $caller, $hasargs, $wantarray) = caller(1);
    my ($package2, $filename2, $line2, $caller2, $hasargs2, $wantarray2) = caller(2);

    #warn "package: $package";
    #warn "filename: $filename";
    #warn "line: $line";
    #warn "caller: $caller";
    #warn "hasargs: $hasargs";
    #warn "wantarray: $wantarray";
    #warn Dumper($self);

    $self->{_package}= $package;
    $self->{_filename}= $filename;
    $self->{_line}= $line;
    $self->{_caller}= $caller;

    $self->{_package2}= $package2;
    $self->{_filename2}= $filename2;
    $self->{_line2}= $line2;
    $self->{_caller2}= $caller2;

    if ($wantarray) {
        return ($retval, $self);
    } elsif ($self->is_success) {
        return $retval;
    } else {
        #die $self->code, " ", $self->message, ". exiting.";
        #croak $self->code, " ", $self->message, ". exiting.";
        #confess $self->code, " ", $self->message, ". exiting.";
        ReturnStatus->throw($self);
    }
}

sub _conditional {
    #warn Dumper(@_);

    my $type;
    my $self;

    my $is_error;
    my $code;
    my $message;
    my $retval;

    #my $mypackage= (caller(0))[0];
    my ($mypackage)= split '::', (caller(0))[3];
    my $wantarray= shift;
    my $return_success= shift;

    # get arguments depending on call type.
    # shift it off if either type info (class method call) 
    # or object ref (call as instantiated object method)
    my ($arg)= @_;
    if (ref($arg) eq $mypackage) {
        $self= shift;
        $type= ref($self);
    } elsif (defined $arg && $arg eq $mypackage) {
        $type= shift;
    }
    # we should now have the caller supplied arguments in @_

    # take a peek at the next argument.
    my $arg2;
    # if called as success(), $retval is the first argument, but we
    # need it last. So move it to the end of the arg array.
    #warn "stack size: " . scalar(@_);
    #warn "stack size: " . $#_;
    if ($return_success) {
        # called with no arguments, push 1 (true) as a return value
        if ($#_ < 0) { push @_, 1; }

        # if we were called with just one value (the return value)
        # push dummy values onto the argument list.
        if ($#_ < 1) { push @_, (undef, undef); }

        push @_, shift;
    }
    ($arg2)= @_;
    #warn "arg2: ", Dumper($arg2);

    # the easy case: we got passed a ReturnStatus object
    # just return the passed object.
    if (ref($arg2) eq $mypackage) {
        ($self, $retval)= @_;
        return ($retval, $self);
        #$self->ret($retval);
    }

    # extract arguments necessary to create a new object.

    # we got passed a Mojo::Message::Response object
    if (ref($arg2) eq "Mojo::Message::Response") {
        (my $res, $retval)= @_;
        $is_error= $res->is_error;
        $code= $res->code;
        $message= $res->message;
        #warn "res: ", Dumper($res);
        #warn "retval: ", Dumper($retval);
    }

    # we got passed an unblessed dictionary
    elsif (defined reftype $arg2 && (reftype $arg2 eq reftype {}) ) {
        #warn "got an unblessed dictionary";
        $is_error= defined $return_success ? ! $return_success : $arg2->{is_error};
        $code= $arg2->{code};
        $message= $arg2->{message};
        $retval= $arg2->{retval};
        #warn Dumper($arg2);
    }

    # just a bunch of arguments
    else {
        # error and success don't pass on $is_error,
        # so take value from $return_success.
        if (defined $return_success) {
            ($code, $message, $retval)= @_;
            #warn "return_success: ", Dumper($return_success);
            $is_error= ! $return_success;
        } else {
            ($is_error, $code, $message, $retval)= @_;
        }
    }

    # decide whether we create a new object or update the existing.

    # we are called as member from an instantiated object.
    # set members to new values and return.
    if (ref($arg) eq $mypackage) {
        $self->{code}= $code;
        $self->{message}= $message;
        $self->{is_error}= $is_error;
        return ($retval, $self);
        #$self->ret($retval);
    }

    # we are called as either a class function or without class or object context.
    # create a new status object.
    $self= ReturnStatus->new($is_error, $code, $message);
  
    return ($retval, $self);
    #$self->ret($retval);
}


sub conditional {
    my $wantarray= (caller(1))[5];
    my $return_success= undef;
    my ($retval, $status)= _conditional($wantarray, $return_success, @_);
    $status->ret($retval);
}

sub error {
    my $wantarray= (caller(1))[5];
    my $return_success= 0;
    my ($retval, $status)= _conditional($wantarray, $return_success, @_);
    $status->ret($retval);
}

sub success {
    my $wantarray= (caller(1))[5];
    my $return_success= 1;
    my ($retval, $status)= _conditional($wantarray, $return_success, @_);
    $status->ret($retval);
}

sub is_error { $_[0]->{is_error}; }
sub is_success { ! $_[0]->{is_error}; }
sub code { $_[0]->{code}; }
sub message { $_[0]->{message}; }
sub line { $_[0]->{_line}; }

1;

