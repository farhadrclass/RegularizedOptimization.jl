# Julia Testing function
using TRNC
using LinearAlgebra, DifferentialEquations, Plots, Random, Zygote, DiffEqSensitivity, Printf, Roots

#In this example, we demonstrate the capacity of the algorithm to minimize a nonlinear
#model with a regularizer
function FHNONLIN()
    
    #Here we solve the Fitzhugh-Nagumo (FHN) Model with some extra terms we know to be zero
    #The FHN model is a set of coupled ODE's 
    #V' = (f(V) - W + I)/μ for f(V) = V - V^3 / 3
    #W' = μ(aV - bW + c) for μ = 0.08,  b = 0.8, c = 0.7

    #so we need a model solution, a gradient, and a Hessian of the system (along with some data to fit)
    function FH_ODE(dx, x, p, t)
        #p is parameter vector [I,μ, a, b, c]
        V,W = x 
        I, μ, a, b, c = p
        dx[1] = (V - V^3/3 -  W + I)/μ
        dx[2] = μ*(a*V - b*W+c)
    end


    u0 = [2.0; 0.0]
    tspan = (0.0, 10.0)
    savetime = .1
    # pars_FH = [.5, 1/12.5, 0.08, 1.0, 0.8, 0.7]
    # pars_FH = [0.5, 0.08, 1.0, 0.8, 0.7,]
    pars_FH = [0.5, 0.08, 1.0, 0.8, 0.7]
    prob_FH = ODEProblem(FH_ODE, u0, tspan, pars_FH)
    sol_FH = solve(prob_FH, reltol=1e-6, saveat=savetime)
    plot(sol_FH, vars=(0,1),xlabel="Time", ylabel="Voltage", label="V", title="FH sol")
    plot!(sol_FH, vars=(0,2),label="W")
    savefig("figs/nonlin/LS_l1_B2/fhn_basic.pdf")


    #So this is all well and good, but we need a cost function and some parameters to fit. First, we take care of the parameters
    #We start by noting that the FHN model is actually the van-der-pol oscillator with some parameters set to zero
    #x' = μ(x - x^3/3 - y)
    #y' = x/μ -> here μ = 12.5
    #changing the parameters to p = [0, .08, 1.0, 0, 0]
    pars_VDP = [0, .2, 1.0, 0, 0]
    prob_VDP = ODEProblem(FH_ODE, u0, tspan, pars_VDP)
    sol_VDP = solve(prob_VDP,reltol=1e-6, saveat=savetime)

    #also make some noie to fit later
    # b = hcat(sol_VDP.u...)[1,:]
    b = hcat(sol_VDP.u...)
    noise = .1*randn(size(b))
    data = noise + b

    plot(sol_VDP, vars=(0,1),xlabel="Time", ylabel="Voltage", label="V", title="VDP sol")
    plot!(sol_VDP, vars=(0,2),label="W")
    plot!(sol_VDP.t, data[1,:], label="V-data")
    plot!(sol_VDP.t, data[2,:], label="W-data")
    savefig("figs/nonlin/LS_l1_B2/vdp_basic.pdf")

    #so now that we have data, we want to formulate our optimization problem. This is going to be 
    #min_p ||f(p) - b||₂^2 + λ||p||₀
    #define your smooth objective function
    #First, make the function you are going to manipulate
    function Gradprob(p)
        temp_prob = remake(prob_FH, p = p)
        temp_sol = solve(temp_prob, reltol=1e-6, saveat=savetime)
        tot_loss = 0.

        if any((temp_sol.retcode!= :Success for s in temp_sol))
            tot_loss = Inf
        else
            temp_v = convert(Array, temp_sol)

            tot_loss = sum((temp_v - data).^2)/2
        end

        return tot_loss
    end
    function f_smooth(x) #gradient and hessian info are smooth parts, m also includes nonsmooth part
        fk = Gradprob(x)
        # @show fk
        if fk==Inf 
            grad = Inf*ones(size(x))
            Hess = Inf*ones(size(x,1), size(x,1))
        else
            grad = Zygote.gradient(Gradprob, x)[1] 
            Hess = Zygote.hessian(Gradprob, x)
        end

        return fk, grad, Hess
    end


    λ = 1.0
    function h_nonsmooth(x)
        # @show x
        return λ*norm(x,0) 
        # return 0
    end


    #put in your initial guesses
    pi = pars_FH

    # (~, sens) = f_smooth(pi)
    (~, ~, Hessapprox) = f_smooth(pi)
    #set all options
    # Doptions=s_options(eigmax(sens*sens'); maxIter=1000, λ=λ, verbose = 0)
    Doptions=s_options(eigmax(Hessapprox); maxIter=1000, λ=λ, verbose = 0)
    # Doptions = spg_options(;optTol=1.0e-1, progTol=1.0e-10, verbose=0, feasibleInit=true, curvilinear=true, bbType=true, memory=1); 

    #all this should be unraveling in the hardproxB# code
    # function prox(q, σ, xk, Δ) #q = s - ν*g, ν*λ, xk, Δ - > basically inputs the value you need

    #     ProjB(y) = min.(max.(y, q.-σ), q.+σ)
    #     froot(η) = η - norm(ProjB((-xk).*(η/Δ)))


    #     # %do the 2 norm projection
    #     y1 = ProjB(-xk) #start with eta = tau
    #     if (norm(y1)<= Δ)
    #         y = y1  # easy case
    #     else
    #         η = fzero(froot, 1e-10, Inf)
    #         y = ProjB((-xk).*(η/Δ))
    #     end

    #     if (norm(y)<=Δ)
    #         snew = y
    #     else
    #         snew = Δ.*y./norm(y)
    #     end
    #     return snew
    # end 
    function prox(q, σ, xk, Δ)

        ProjB(y) = min.(max.(y, xk.-Δ),xk.+Δ) # define outside? 
        c = sqrt(2*σ)
        w = xk+q
        st = zeros(size(w))

        for i = 1:length(w)
            absx = abs(w[i])
            if absx <=c
                st[i] = 0
            else
                st[i] = w[i]
            end
        end
        s = ProjB(st) - xk
        return s 
    end
    #h = 0
    function tr_norm(z,σ)
        return z./max(1, norm(z, 2)/σ)
    end
    # function tr_norm_spg(z,α,σ)
    #     return z./max(1, norm(z, 2)/σ)
    # end


    parameters = IP_struct(f_smooth, h_nonsmooth;
        s_alg = PG, FO_options = Doptions, Rkprox = prox) 
        # FO_options = Doptions, Rk = tr_norm_spg); 

    # options = IP_options(; ptf=1, ϵD = 1e-4)
    options = IP_options(; ptf=1, ϵD = 1e-5)

    p, k, Fhist, Hhist = IntPt_TR(pi, parameters, options);# u = u, l=l, μ = 100, BarIter = 20)

    myProbFH = remake(prob_FH, p = p)
    sol = solve(myProbFH; reltol=1e-6, saveat = savetime)

    #print out l2 norm difference and plot the two x values
    @printf("l2-norm True vs TR: %5.5e\n", norm(pars_VDP - p)/norm(p))

    @printf("Full Objective -  TR: %5.5e    True: %5.5e\n",
    f_smooth(p)[1]+h_nonsmooth(p), f_smooth(pars_VDP)[1]+h_nonsmooth(pars_VDP))

    @printf("f(x) -  TR: %5.5e  True: %5.5e\n",
    f_smooth(p)[1],  f_smooth(pars_VDP)[1])

    @printf("h(x) -  TR: %5.5e    True: %5.5e\n",
    h_nonsmooth(p)/λ, h_nonsmooth(pars_VDP)/λ)

    plot(sol_VDP, vars=(0,1), xlabel="Time", ylabel="Voltage", label="VDP-V", title="True vs TR")
    plot(sol_VDP, vars=(0,2), label="VDP-W")
    plot!(sol, vars=(0,1), label="tr", marker=2)
    plot!(sol, vars=(0,2), label="tr", marker=2)
    plot!(sol_VDP.t, data[1,:], label="V-data")
    plot!(sol_VDP.t, data[2,:], label="W-data")
    savefig("figs/nonlin/LS_l1_B2/vcomp.pdf")


    plot(Fhist, xlabel="k^th index", ylabel="Function Value", title="Objective Value History", label="f(x)")
    plot!(Hhist, label="h(x)")
    plot!(Fhist + Hhist, label="f+h")
    savefig("figs/nonlin/LS_l1_B2/objhist.pdf")
end