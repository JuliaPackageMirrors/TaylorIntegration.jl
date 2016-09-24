# This file is part of the TaylorIntegration.jl package; MIT licensed


# jetcoeffs!
doc"""
    jetcoeffs!(f, t, x)

Returns an updated `x` using the recursion relation of the
derivatives from the ODE $\dot{x}=dx/dt=f(t,x)$.

`f` is the function defining the RHS of the ODE, `x` is a `Taylor1{T}`
or a vector of that type, containing the Taylor expansion
of the dependent variables of the ODE and `t` is the independent
variable.
Initially, `x` contains only the 0-th order Taylor coefficients of
the current system state (the initial conditions), and `jetcoeffs!`
computes recursively the high-order derivates back into `x`.
"""
function jetcoeffs!{T<:Number}(eqsdiff, t0::T, x::Taylor1{T})
    order = x.order
    for ord in 1:order
        ordnext = ord+1

        # Set `xaux`, auxiliary Taylor1 variable to order `ord`
        @inbounds xaux = Taylor1( x.coeffs[1:ord] )

        # Equations of motion
        # TODO! define a macro to optimize the eqsdiff
        xdot = eqsdiff(t0, xaux)

        # Recursion relation
        @inbounds x.coeffs[ordnext] = xdot.coeffs[ord]/ord
    end
    nothing
end

function jetcoeffs!{T<:Number}(eqsdiff, t0::T, x::Vector{Taylor1{T}})
    order = x[1].order
    xaux = similar(x)
    for ord in 1:order
        ordnext = ord+1

        # Set `xaux`, auxiliary vector of Taylor1 to order `ord`
        @inbounds for j in eachindex(x)
            xaux[j] = Taylor1( x[j].coeffs[1:ord] )
        end

        # Equations of motion
        # TODO! define a macro to optimize the eqsdiff
        xdot = eqsdiff(t0, xaux)

        # Recursion relations
        @inbounds for j in eachindex(x)
            x[j].coeffs[ordnext] = xdot[j].coeffs[ord]/ord
        end
    end
    nothing
end

doc"""
Experimental version of jetcoeffs!, where `xaux` and `xdot` are passed by
reference. This was done searching for performance. Will be better
documented in the future, if it works well. -JAPH
"""
function jetcoeffs!{T<:Number}(eqsdiff, t0::T, x::Vector{Taylor1{T}},
    xdot::Vector{Taylor1{T}}, xaux::Vector{Taylor1{T}})

    order = x[1].order
    #xaux = similar(x)
    for ord in 1:order
        ordnext = ord+1

        # Set `xaux`, auxiliary vector of Taylor1 to order `ord`
        @inbounds for j in eachindex(x)
            xaux[j] = Taylor1( x[j].coeffs[1:ord] )
        end

        # Equations of motion
        # TODO! define a macro to optimize the eqsdiff
        eqsdiff(t0, xaux, xdot)

        # Recursion relations
        @inbounds for j in eachindex(x)
            x[j].coeffs[ordnext] = xdot[j].coeffs[ord]/ord
        end
    end
    nothing
end


# stepsize
doc"""
    stepsize(x, epsilon)

Returns a time-step for a `x::Taylor1{T}` using a
prescribed absolute tolerance `epsilon`.
"""
function stepsize{T<:Number}(x::Taylor1{T}, epsilon::T)
    ord = x.order
    h = T(Inf)
    for k in (ord-1, ord)
        @inbounds aux = abs( x.coeffs[k+1] )
        aux == zero(T) && continue
        aux = epsilon / aux
        kinv = one(T)/k
        aux = aux^kinv
        h = min(h, aux)
    end
    return h
end

doc"""
    stepsize(q, epsilon)

Returns the minimum time-step for `q::Array{Taylor1{T},1}`,
using a prescribed absolute tolerance `epsilon`.
"""
function stepsize{T<:Number}(q::Array{Taylor1{T},1}, epsilon::T)
    h = T(Inf)
    for i in eachindex(q)
        @inbounds hi = stepsize( q[i], epsilon )
        h = min( h, hi )
    end
    return h
end


# taylorstep and taylorstep!
doc"""
    taylorstep(f, t0, x0, order, abs_tol)

Compute one-step Taylor integration for the ODE $\dot{x}=dx/dt=f(t, x)$
with initial condition $x(t_0)=x0$, returning the
time-step of the integration carried out and the updated value of `x0`.

Here, `x0` is the initial (and returned) dependent variable, `order`
is the degree used for the `Taylor1` polynomials during the integration
and `abs_tol` is the absolute tolerance used to determine the time step
of the integration.
"""
function taylorstep{T<:Number}(f, t0::T, x0::T, order::Int, abs_tol::T)
    # Initialize the Taylor1 expansions
    xT = Taylor1( x0, order )
    # Compute the Taylor coefficients
    jetcoeffs!(f, t0, xT)
    # Compute the step-size of the integration using `abs_tol`
    δt = stepsize(xT, abs_tol)
    x0 = evaluate(xT, δt)
    return δt, x0
end

doc"""
    taylorstep!(f, t0, x0, order, abs_tol)

Compute one-step Taylor integration for the ODE $\dot{x}=dx/dt=f(t, x)$
with initial conditions $x(t_0)=x0$, a vector of type T, returning the
step-size of the integration; `x0` is updated.

Here, `x0` is the initial (and updated) dependent variables, `order`
is the degree used for the `Taylor1` polynomials during the integration
and `abs_tol` is the absolute tolerance used to determine the time step
of the integration.
"""
function taylorstep!{T<:Number}(f, t0::T, x0::Array{T,1}, order::Int, abs_tol::T)
    # Initialize the vector of Taylor1 expansions
    xT = Array{Taylor1{T}}(length(x0))
    for i in eachindex(x0)
        @inbounds xT[i] = Taylor1( x0[i], order )
    end
    # Compute the Taylor coefficients
    jetcoeffs!(f, t0, xT)
    # Compute the step-size of the integration using `abs_tol`
    δt = stepsize(xT, abs_tol)
    evaluate!(xT, δt, x0)
    return δt
end

doc"""
    WARNING! CURRENT STATUS: EXPERIMENTAL:
    taylorstep!{T<:Number}(f, t0::T, t1::T, x0::Array{T,1}, xT::Array{Taylor1{T}},
            xdotT::Array{Taylor1{T},1}, xaux::Array{Taylor1{T},1}, order::Int, abs_tol::T)

    Executes an iteration of a Taylor method integration. Same as similar
    method of taylorstep!, but passes as much data as possible by reference,
    instead of allocating new arrays and returning them. Note the use of
    `evaluate2!` (also experimental), instead of `TaylorSeries.evaluate!`.  -JAPH

"""
function taylorstep!{T<:Number}(f, t0::T, x0::Array{T,1}, xT::Array{Taylor1{T}},
    xdotT::Array{Taylor1{T},1}, xaux::Array{Taylor1{T},1}, order::Int, abs_tol::T)
    # Initialize the vector of Taylor1 expansions
    #xT = Array{Taylor1{T}}(length(x0))
    # for i in eachindex(x0)
    #     @inbounds xT[i] = Taylor1( x0[i], order )
    # end
    # Compute the Taylor coefficients
    jetcoeffs!(f, t0, xT, xdotT, xaux)
    # Compute the step-size of the integration using `abs_tol`
    δt = stepsize(xT, abs_tol)
    evaluate2!(xT, δt, x0)
    return δt
end

doc"""
    taylorstep(f, t0, t1, x0, order, abs_tol)

Compute one-step Taylor integration for the ODE $\dot{x}=dx/dt=f(t, x)$
with initial conditions $x(t_0)=x0$, returning the
time-step of the integration carried out and the updated value of `x0`.

Here, `x0` is the initial (and returned) dependent variables, `order`
is the degree used for the `Taylor1` polynomials during the integration
and `abs_tol` is the absolute tolerance used to determine the time step
of the integration. If the time step is larger than `t1-t0`, that difference
is used as the time step.
"""
function taylorstep{T<:Number}(f, t0::T, t1::T, x0::T, order::Int, abs_tol::T)
    @assert t1 > t0
    # Initialize the Taylor1 expansions
    xT = Taylor1( x0, order )
    # Compute the Taylor coefficients
    jetcoeffs!(f, t0, xT)
    # Compute the step-size of the integration using `abs_tol`
    δt = stepsize(xT, abs_tol)
    if δt ≥ t1-t0
        δt = t1-t0
    end
    x0 = evaluate(xT, δt)
    return δt, x0
end

doc"""
    taylorstep!(f, t0, t1, x0, order, abs_tol)

Compute one-step Taylor integration for the ODE $\dot{x}=dx/dt=f(t, x)$
with initial conditions $x(t_0)=x0$, a vector of type T, returning the
step-size of the integration carried out and updating `x0`.

Here, `x0` is the initial (and updated) dependent variables, `order`
is the degree used for the `Taylor1` polynomials during the integration
and `abs_tol` is the absolute tolerance used to determine the time step
of the integration. If the time step is larger than `t1-t0`, that difference
is used as the time step.
"""
function taylorstep!{T<:Number}(f, t0::T, t1::T, x0::Array{T,1},
        order::Int, abs_tol::T)
    @assert t1 > t0
    # Initialize the vector of Taylor1 expansions
    xT = Array{Taylor1{T}}(length(x0))
    for i in eachindex(x0)
        @inbounds xT[i] = Taylor1( x0[i], order )
    end
    # Compute the Taylor coefficients
    jetcoeffs!(f, t0, xT)
    # Compute the step-size of the integration using `abs_tol`
    δt = stepsize(xT, abs_tol)
    if δt ≥ t1-t0
        δt = t1-t0
    end
    evaluate!(xT, δt, x0)
    return δt
end

doc"""
    WARNING! CURRENT STATUS: EXPERIMENTAL:
    taylorstep!{T<:Number}(f, t0::T, t1::T, x0::Array{T,1}, xT::Array{Taylor1{T}},
            xdotT::Array{Taylor1{T},1}, xaux::Array{Taylor1{T},1}, order::Int, abs_tol::T)

    Executes an iteration of a Taylor method integration. Same as similar
    method of taylorstep!, but passes as much data as possible by reference,
    instead of allocating new arrays and returning them. Note the use of
    `evaluate2!` (also experimental), instead of `TaylorSeries.evaluate!`.  -JAPH

"""
function taylorstep!{T<:Number}(f, t0::T, t1::T, x0::Array{T,1}, xT::Array{Taylor1{T}},
        xdotT::Array{Taylor1{T},1}, xaux::Array{Taylor1{T},1}, order::Int, abs_tol::T)
    @assert t1 > t0
    # Initialize the vector of Taylor1 expansions
    # xT = Array{Taylor1{T}}(length(x0))
    # for i in eachindex(x0)
    #     @inbounds xT[i] = Taylor1( x0[i], order )
    # end
    # Compute the Taylor coefficients
    jetcoeffs!(f, t0, xT, xdotT, xaux)
    # Compute the step-size of the integration using `abs_tol`
    δt = stepsize(xT, abs_tol)
    if δt ≥ t1-t0
        δt = t1-t0
    end
    #use experimental method evaluate2!
    evaluate2!(xT, δt, x0)
    return δt
end


# taylorinteg
doc"""
    taylorinteg(f, x0, t0, tmax, order, abs_tol; keyword... )

This is a general-purpose Taylor integrator for the explicit ODE
$\dot{x}=f(t,x)$ with initial condition specified by `x0` at time `t0`.
It returns a vector with the values of time (independent variable),
and a vector (of type `typeof(x0)`) with the computed values of
the dependent variables. The integration stops when time
is larger than `tmax`, or the number of saved steps is larger
than `maxsteps`.

The integrator uses polynomial expansions on the independent variable
of order `order` and the parameter `abs_tol` serves to define the
time step using the last two Taylor coefficients of the expansions.

The current keyword argument is `maxsteps=500`.
"""
function taylorinteg{T<:Number}(f, x0::T, t0::T, t_max::T,
        order::Int, abs_tol::T; maxsteps::Int=500)

    # Allocation
    tv = Array{T}(maxsteps+1)
    xv = Array{T}(maxsteps+1)

    # Initial conditions
    nsteps = 1
    @inbounds tv[1] = t0
    @inbounds xv[1] = x0

    # Integration
    while t0 < t_max
        xold = x0
        δt, x0 = taylorstep(f, t0, x0, order, abs_tol)
        if t0+δt ≥ t_max
            x0 = xold
            δt, x0 = taylorstep(f, t0, t_max, x0, order, abs_tol)
            t0 = t_max
            nsteps += 1
            @inbounds tv[nsteps] = t0
            @inbounds xv[nsteps] = x0
            break
        end
        t0 += δt
        nsteps += 1
        @inbounds tv[nsteps] = t0
        @inbounds xv[nsteps] = x0
        if nsteps > maxsteps
            warn("""
            Maximum number of integration steps reached; exiting.
            """)
            break
        end
    end

    #return tv, xv
    return view(tv,1:nsteps), view(xv,1:nsteps)
end

function taylorinteg{T<:Number}(f, q0::Array{T,1}, t0::T, t_max::T,
        order::Int, abs_tol::T; maxsteps::Int=500)

    # Allocation
    tv = Array{T}(maxsteps+1)
    dof = length(q0)
    xv = Array{eltype(q0)}(dof, maxsteps+1)

    # Initial conditions
    @inbounds tv[1] = t0
    @inbounds xv[:,1] = q0[:]
    x0 = copy(q0)

    # Integration
    nsteps = 1
    while t0 < t_max
        xold = x0
        δt = taylorstep!(f, t0, x0, order, abs_tol)
        if t0+δt ≥ t_max
            x0 = xold
            δt = taylorstep!(f, t0, t_max, x0, order, abs_tol)
            t0 = t_max
            nsteps += 1
            @inbounds tv[nsteps] = t0
            @inbounds xv[:,nsteps] = x0[:]
            break
        end
        t0 += δt
        nsteps += 1
        @inbounds tv[nsteps] = t0
        @inbounds xv[:,nsteps] = x0[:]
        if nsteps > maxsteps
            warn("""
            Maximum number of integration steps reached; exiting.
            """)
            break
        end
    end

    #return tv, xv'
    return view(tv,1:nsteps), view(xv',1:nsteps,:)
end

doc"""
    WARNING: CURRENT STATUS: EXPERIMENTAL
    evaluate2!{T<:Number}(x::Array{Taylor1{T},1}, δt::T, x0::Array{T,1})

This method is similar to TaylorSeries.evaluate! (see docs), the only difference is
that after evaluating the Taylor expansion into `x0`, the values are copied
back into the `Taylor1` array `x`. This is aimed towards improving performance
and should avoid the necessity of creating new arrays, pass most data by reference,
and helps to pass the same object `x` (a Taylor1 array) among taylorinteg,
taylorstep!, and jetcoeffs!. If this change happens to improve performance, it
will be better documented in the near future. -JAPH
"""
function evaluate2!{T<:Number}(x::Array{Taylor1{T},1}, δt::T, x0::Array{T,1})
            #making sure of safe use of inbounds
           @assert length(x) == length(x0)
           #evaluate Taylor expansions, put the result into x0.
           @inbounds for i in eachindex(x)
               x0[i] = evaluate( x[i], δt )
           end
           #for each element, copy x0 into first coeff of x.
           @inbounds for i in eachindex(x)
               x[i].coeffs[1] = x0[i]
           end
          nothing
end

doc"""
    WARNING: CURRENT STATUS: EXPERIMENTAL
    taylorinteg2{T<:Number}(f, q0::Array{T,1}, t0::T, t_max::T, order::Int, abs_tol::T; maxsteps::Int=500)

This method is an experiment directed towards improving performance of
`TaylorIntegration.jl`. It is essentially the same as `taylorinteg` (see docs),
but tries to pass as much data as possible by reference, instead of creating
new arrays along the way. If this change happens to improve performance, it
will be better documented in the near future. -JAPH
"""
function taylorinteg2{T<:Number}(f, q0::Array{T,1}, t0::T, t_max::T,
        order::Int, abs_tol::T; maxsteps::Int=500)

    # Allocation
    tv = Array{T}(maxsteps+1)
    dof = length(q0)
    xv = Array{eltype(q0)}(dof, maxsteps+1)
    xdotT = Array{Taylor1{eltype(q0)}}(dof)
    #xaux = similar(x)
    xaux = Array{Taylor1{eltype(q0)}}(dof)

    # Initial conditions
    @inbounds tv[1] = t0
    @inbounds xv[:,1] = q0[:]
    x0 = copy(q0)

    # Initialize the vector of Taylor1 expansions
    x0T = Array{Taylor1{T}}(length(x0))
    for i in eachindex(x0)
        @inbounds x0T[i] = Taylor1( x0[i], order )
    end

    # Integration
    nsteps = 1
    while t0 < t_max
        xold = x0
        δt = taylorstep!(f, t0, x0, x0T, xdotT, xaux, order, abs_tol)
        if t0+δt ≥ t_max
            x0 = xold
            δt = taylorstep!(f, t0, t_max, x0, x0T, xdotT, xaux, order, abs_tol)
            t0 = t_max
            nsteps += 1
            @inbounds tv[nsteps] = t0
            @inbounds xv[:,nsteps] = x0[:]
            break
        end
        t0 += δt
        nsteps += 1
        @inbounds tv[nsteps] = t0
        @inbounds xv[:,nsteps] = x0[:]
        if nsteps > maxsteps
            warn("""
            Maximum number of integration steps reached; exiting.
            """)
            break
        end
    end

    #return tv, xv'
    return view(tv,1:nsteps), view(xv',1:nsteps,:)
end

# Integrate and return results evaluated at given time
function taylorinteg{T<:Number}(f, x0::T, trange::Range{T},
        order::Int, abs_tol::T; maxsteps::Int=500)

    # Allocation
    nn = length(trange)
    xv = Array{T,1}(nn)
    fill!(xv, T(NaN))

    # Initial conditions
    @inbounds xv[1] = x0

    # Integration
    iter = 1
    while iter < nn
        t0, t1 = trange[iter], trange[iter+1]
        nsteps = 0
        while nsteps < maxsteps
            xold = x0
            δt, x0 = taylorstep(f, t0, x0, order, abs_tol)
            if t0+δt ≥ t1
                x0 = xold
                δt, x0 = taylorstep(f, t0, t1, x0, order, abs_tol)
                t0 = t1
                break
            end
            t0 += δt
            nsteps += 1
        end
        if nsteps ≥ maxsteps && t0 != t1
            warn("""
            Maximum number of integration steps reached; exiting.
            """)
            break
        end
        iter += 1
        @inbounds xv[iter] = x0
    end

    return xv
end

function taylorinteg{T<:Number}(f, q0::Array{T,1}, trange::Range{T},
        order::Int, abs_tol::T; maxsteps::Int=500)

    # Allocation
    nn = length(trange)
    dof = length(q0)
    x0 = similar(q0, T, dof)
    fill!(x0, T(NaN))
    xv = Array{eltype(q0)}(dof, nn)
    @inbounds for ind in 1:nn
        xv[:,ind] = x0[:]
    end

    # Initial conditions
    @inbounds x0[:] = q0[:]
    @inbounds xv[:,1] = q0[:]

    # Integration
    iter = 1
    while iter < nn
        t0, t1 = trange[iter], trange[iter+1]
        nsteps = 0
        while nsteps < maxsteps
            xold = copy(x0)
            δt = taylorstep!(f, t0, x0, order, abs_tol)
            if t0+δt ≥ t1
                x0 = xold
                δt = taylorstep!(f, t0, t1, x0, order, abs_tol)
                t0 = t1
                break
            end
            t0 += δt
            nsteps += 1
        end
        if nsteps ≥ maxsteps && t0 != t1
            warn("""
            Maximum number of integration steps reached; exiting.
            """)
            break
        end
        iter += 1
        @inbounds xv[:,iter] = x0[:]
    end

    return xv'
end
