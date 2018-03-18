export collisiontime
#######################################################################################
## Particle
#######################################################################################
"""
    collisiontime(p::AbstractParticle, o::Obstacle)
Calculate the collision time (time-until-collision) between given
particle and obstacle. Returns `Inf` if the collision is not possible *or* if the
collision happens backwards in time.

In the case of magnetic propagation, there are always two possible collisions.
The function internally decides which of the two will occur first, based on the
sign of the angular velocity of the magnetic particle.
"""
function collisiontime(p::Particle{T}, w::Wall{T})::T where {T}
    n = normalvec(w, p.pos)
    denom = dot(p.vel, n)
    denom >= 0 ? Inf : dot(w.sp-p.pos, n)/denom
end

function collisiontime(p::Particle{T}, w::FiniteWall{T})::T where {T}
    n = normalvec(w, p.pos)
    denom = dot(p.vel, n)
    # case of velocity pointing away of wall:
    denom ≥ 0 && return Inf
    posdot = dot(w.sp-p.pos, n)
    # Case of particle starting behind finite wall:
    posdot ≥ 0 && return Inf
    colt = posdot/denom
    intersection = p.pos .+ colt .* p.vel
    dfc = norm(intersection - w.center)
    if dfc > w.width/2
        return Inf
    else
        return colt
    end
end

function collisiontime(p::Particle{T}, d::Circular{T})::T where {T}

    dotp = dot(p.vel, normalvec(d, p.pos))
    dotp >=0 && return Inf

    dc = p.pos - d.c
    B = dot(p.vel, dc)         #pointing towards circle center: B < 0
    C = dot(dc, dc) - d.r^2    #being outside of circle: C > 0
    Δ = B^2 - C

    Δ <= 0 && return Inf
    sqrtD = sqrt(Δ)

    # Closest point:
    t = -B - sqrtD
    t <=0 ? Inf : t
end

function collisiontime(p::Particle{T}, d::Antidot{T})::T where {T}

    dotp = dot(p.vel, normalvec(d, p.pos))
    if d.pflag == true
        dotp >=0 && return Inf
    end

    dc = p.pos - d.c
    B = dot(p.vel, dc)         #velocity towards circle center: B < 0
    C = dot(dc, dc) - d.r^2    #being outside of circle: C > 0
    Δ = B^2 - C

    Δ <= 0 && return Inf
    sqrtD = sqrt(Δ)

    # Closest point (may be in negative time):
    if dotp < 0
        t = -B - sqrtD
    else
        t = -B + sqrtD
    end

    # If collision time is negative, return Inf:
    t <= 0.0 ? Inf : t
end

function collisiontime(p::Particle{T}, d::Semicircle{T})::T where {T}

    dc = p.pos - d.c
    B = dot(p.vel, dc)         #velocity towards circle center: B > 0
    C = dot(dc, dc) - d.r^2    #being outside of circle: C > 0
    Δ = B^2 - C

    Δ <= 0 && return Inf
    sqrtD = sqrt(Δ)

    nn = dot(dc, d.facedir)
    if nn ≥ 0 # I am NOT inside semicircle
        # Return most positive time
        t = -B + sqrtD
    else # I am inside semicircle:
        # these lines make sure that the code works for ANY starting position:
        t = -B - sqrtD
        if t ≤ 0 || distance(p, d) ≤ distancecheck(T)
            t = -B + sqrtD
        end
    end
    # This check is necessary to not collide with the non-existing side
    newpos = p.pos + p.vel .* t
    if dot(newpos - d.c, d.facedir) ≥ 0 # collision point on BAD HALF;
        return Inf
    end
    # If collision time is negative, return Inf:
    t ≤ 0.0 ? Inf : t
end



#######################################################################################
## Magnetic particle
#######################################################################################
function collisiontime(p::MagneticParticle{T}, w::Wall{T})::T where {T}
    ω = p.omega
    pc, pr = cyclotron(p)
    P0 = p.pos
    P2P1 = w.ep - w.sp
    P1P3 = w.sp - pc
    # Solve quadratic:
    a = dot(P2P1, P2P1)
    b = 2*dot(P2P1, P1P3)
    c = dot(P1P3, P1P3) - pr^2
    Δ = b^2 -4*a*c
    # Check if line is completely outside (or tangent) of the circle:
    Δ ≤ 0.0 && return Inf
    # Intersection coefficients:
    u1 = (-b - sqrt(Δ))/2a
    u2 = (-b + sqrt(Δ))/2a
    cond1 = (0.0 ≤ u1 ≤ 1.0)
    cond2 = (0.0 ≤ u2 ≤ 1.0)
    # Check if the line is completely inside the circle:
    if cond1 || cond2
        I1 = w.sp + u1*(w.ep - w.sp)
        I2 = w.sp + u2*(w.ep - w.sp)
        # Calculate real time until intersection:
        θ = cond1 ? (
            cond2 ? realangle(p, w, pc, pr, I1, I2) : realangle(p, w, pc, pr, I1)
            ) : realangle(p, w, pc, pr, I2)
    else
        return Inf
    end
    # Collision time, equiv. to arc-length until collision point:
    return θ*pr
end

function collisiontime(p::MagneticParticle{T}, o::Circular{T})::T where {T}
    ω = p.omega
    pc, rc = cyclotron(p)
    p1 = o.c
    r1 = o.r
    d = norm(p1-pc)
    if (d >= rc + r1) || (d <= abs(rc-r1))
        return Inf
    end
    # Solve quadratic:
    a = (rc^2 - r1^2 + d^2)/2d
    h = sqrt(rc^2 - a^2)
    # Collision points (always 2):
    I1 = SVector{2, T}(
    pc[1] + a*(p1[1] - pc[1])/d + h*(p1[2] - pc[2])/d,
    pc[2] + a*(p1[2] - pc[2])/d - h*(p1[1] - pc[1])/d)
    I2 = SVector{2, T}(
    pc[1] + a*(p1[1] - pc[1])/d - h*(p1[2] - pc[2])/d,
    pc[2] + a*(p1[2] - pc[2])/d + h*(p1[1] - pc[1])/d)
    # Calculate real time until intersection:
    θ = realangle(p, o, pc, rc, I1, I2)
    # Collision time, equiv. to arc-length until collision point:
    return θ*rc
end

function collisiontime(p::MagneticParticle{T}, o::Semicircle{T})::T where {T}
    ω = p.omega
    pc, rc = cyclotron(p)
    p1 = o.c
    r1 = o.r
    d = norm(p1-pc)
    if (d >= rc + r1) || (d <= abs(rc-r1))
        return Inf
    end
    # Solve quadratic:
    a = (rc^2 - r1^2 + d^2)/2d
    h = sqrt(rc^2 - a^2)
    # Collision points (always 2):
    I1 = SVector{2, T}(
    pc[1] + a*(p1[1] - pc[1])/d + h*(p1[2] - pc[2])/d,
    pc[2] + a*(p1[2] - pc[2])/d - h*(p1[1] - pc[1])/d)
    I2 = SVector{2, T}(
    pc[1] + a*(p1[1] - pc[1])/d - h*(p1[2] - pc[2])/d,
    pc[2] + a*(p1[2] - pc[2])/d + h*(p1[1] - pc[1])/d)
    # Only consider intersections on the "correct" side of Semicircle:
    cond1 = dot(I1-o.c, o.facedir) < 0
    cond2 = dot(I2-o.c, o.facedir) < 0
    if cond1 || cond2
        # Calculate real time until intersection:
        θ = cond1 ? (
            cond2 ? realangle(p, o, pc, rc, I1, I2) : realangle(p, o, pc, rc, I1)
            ) : realangle(p, o, pc, rc, I2)
    else
        return Inf
    end
    # Collision time, equiv. to arc-length until collision point:
    return θ*rc
end

"""
    realangle(p::MagneticParticle, o::Obstacle, pc, pr, Ii...)
Given the intersections `Ii...` of the trajectory of a magnetic particle `p` with
some obstacle `o`, find which of them is the the "real" one, i.e. occurs first.
Returns the angle of first collision, which is equal to the time to first
collision divided by ω (or multiplied by r).

The function also takes care of problems that may arise when particles are very
close to the obstacle's boundaries, due to floating-point precision.

(the cyclotron center `pc` and radius `pr` are suplimented for efficiency, since they
have been calculated already)
"""
function realangle(p::MagneticParticle{T}, o::Obstacle{T},
    pc::SVector{2, T}, pr::T, Ii::Vararg{SV{T}})::T where {T}

    ω = p.omega
    P0 = p.pos
    PC = pc - P0
    θ::T = Inf
    for i in Ii
        d2 = dot(i-P0,i-P0) #distance of particle from intersection point
        # Check dot product for close points:
        if d2 ≤ distancecheck(T)
            dotp = dot(p.vel, normalvec(o,  p.pos))
            # Case where velocity points away from obstacle:
            dotp ≥ 0 && continue
        end

        d2r = (d2/(2pr^2))
        d2r > 2 && (d2r = T(2.0))
        # Correct angle value for small arguments (between 0 and π/2):
        θprime = d2r < 1e-3 ? acos1mx(d2r) : acos(1.0 - d2r)

        # Get "side" of i:
        PI = i - P0
        side = (PI[1]*PC[2] - PI[2]*PC[1])*ω
        # Get angle until i (positive number between 0 and 2π)
        side < 0 && (θprime = T(2π-θprime))
        # Set minimum angle (first collision)
        if θprime < θ
            θ = θprime
        end
    end
    return θ
end



#######################################################################################
## next_collision
#######################################################################################
"""
    next_collision(p, bt) -> (tmin, index)
Return the minimum collision time out of all `collisiontime(p, obst)` for `obst ∈ bt`,
as well as the `index` of the corresponding obstacle.
"""
function next_collision(
    p::AbstractParticle{T}, bt::Tuple)::Tuple{T,Int} where {T}
    findmin(Unrolled.unrolled_map(x -> collisiontime(p, x), bt))
end

@inline next_collision(p::AbstractParticle, bt::BilliardTable) =
    next_collision(p, bt.bt)

function next_collision(
    p::AbstractParticle{T}, bt::Vector{<:Obstacle{T}})::Tuple{T,Int} where {T}
    tmin::T = T(Inf)
    ind::Int = 0
    for i in eachindex(bt)
        tcol::T = collisiontime(p, bt[i])
        # Set minimum time:
        if tcol < tmin
            tmin = tcol
            ind = i
        end
    end#obstacle loop
    return tmin, ind
end

### OTher attempts:
# function next_collision(
#     p::AbstractParticle{T}, bt::Tuple)::Tuple{T,Int} where {T}
#     findmin(map(x -> collisiontime(p, x), bt))
# end
#
# using Unrolled
# @unroll function next_collision2(p::AbstractParticle{T}, bt::Tuple) where {T}
#     tmin::T = T(Inf)
#     ind::Int = 0
#     i::Int = 0
#     @unroll for obst in bt
#         tcol::T = collisiontime(p, obst)
#         i+=1
#         # Set minimum time:
#         if tcol < tmin
#             tmin = tcol
#             ind = i
#         end
#     end#obstacle loop
#     return tmin, ind
# end
