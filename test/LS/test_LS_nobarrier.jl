# Julia Testing function
using Plots

#Here we just try to solve the l2-norm Problem over the l1 trust region
#######
# min_x 1/2||Ax - b||^2
function LSnobar(A, x0, b, b0)
    m,n= size(A)
    function f_obj(x)
        f = .5*norm(A*x-b)^2
        g = A'*(A*x - b)
        # h = A'*A #-> BFGS later
        h(d) = A'*(A*d)
        return f, g, h
    end

    #SPGSlim version
    function tr_norm_spg(z,α,σ)
        return z./max(1, norm(z, 2)/σ)
    end

    function tr_norm(z,σ, x, Δ)
        return z./max(1, norm(z, 2)/σ)
    end

    function h_obj(x)
        return 0
    end

    #set all options
    first_order_options_spgslim = spg_options(;optTol=1.0e-1, progTol=1.0e-10, verbose=0,
        feasibleInit=true, curvilinear=true, bbType=true, memory=1)
    first_order_options_proj = s_options(1/eigmax(A'*A);maxIter=1000, verbose=0, optTol=1.0e-3)
        #need to tighten this because you don't make any progress in the later iterations


    # Interior Pt Algorithm
    parameters_spgslim = IP_struct(f_obj, h_obj;
        FO_options = first_order_options_spgslim, Rkprox=tr_norm_spg) #defaults to h=0, spgl1/min_confSPG
    parameters_proj = IP_struct(f_obj, h_obj;
        s_alg = PG, FO_options = first_order_options_proj, Rkprox=tr_norm)
    # parameters = IP_struct(f_obj, h_obj;FO_options = first_order_options, Rk=tr_norm) #defaults to h=0, spgl1/min_confSPG
    options_spgslim = IP_options(; verbose=0, ϵD=1e-4) #print freq, ΔK init, epsC/epsD initialization, maxIter
    options_proj= IP_options(;verbose=0, ϵD=1e-4)

    opt = () -> SCS.Optimizer(verbose=false)
    #put in your initial guesses
    xi = ones(n,)/2

    X = Variable(n)
    problem = minimize(sumsquares(A * X - b))
    solve!(problem, opt)


    x_spg, k, Fhist_spg, Hhist_spg, Comp_spg = IntPt_TR(xi, parameters_spgslim, options_spgslim)
    x_pr, k, Fhist_pg, Hhist_pg, Comp_pg = IntPt_TR(xi, parameters_proj, options_proj)


    # #print out l2 norm difference and plot the two x values
    # @printf("l2-norm TR (SPGSlim) vs True: %5.5e\n", )
    # @printf("l2-norm TR (PG) vs True: %5.5e\n", )
    # @printf("l2-norm CVX vs True: %5.5e\n", )
    # @printf("TR (SPGSlim) vs CVX relative error: %5.5e\n", )
    # @printf("TR (PG) vs CVX relative error: %5.5e\n", )
    # @printf("TR - Fevals: %5.5e vs SPG - Fevals: %5.5e\n", )
   
    
    
    plot(x0, xlabel="i^th index", ylabel="x", title="TR vs True x", label="True x")
    plot!(x_spg, label="tr-spg", marker=2)
    plot!(x_pr, label="tr-pr", marker=3)
    plot!(X.value, label="cvx")
    savefig("figs/ls/xcomp.pdf")

    plot(b0, xlabel="i^th index", ylabel="b", title="TR vs True x", label="True b")
    plot!(b, label="Observed")
    plot!(A*x_spg, label="A*x: TR-spg", marker=2)
    plot!(A*x_pr, label="A*x: TR-pr", marker=3)
    plot!(A*X.value, label="A*x: CVX")
    savefig("figs/ls/bcomp.pdf")

    plot(Fhist_spg, xlabel="k^th index", ylabel="Function Value", title="Objective Value History", label="f(x) (SPGSlim)",  yaxis=:log)
    plot!(Hhist_spg, label="h(x) (SPGSlim)")
    plot!(Fhist_spg + zeros(size(Fhist_spg)), label="f+h (SPGSlim)")
    plot!(Hhist_pg, label="h(x) (Prox-grad)")
    plot!(Fhist_pg, label="f(x) (Prox-grad)")
    plot!(Fhist_pg + zeros(size(Fhist_pg)), label="f+h (Prox-grad)")
    savefig("figs/ls/objhist.pdf")

    plot(Comp_pg, xlabel="k^th index", ylabel="Function Calls per Iteration", title="Complexity History", label="TR")
    plot!(Comp_spg, label="SPG")
    savefig("figs/ls/complexity.pdf")  

    return norm(x_spg - x0)/norm(x0), norm(x_pr - x0)/norm(x0), norm(X.value - x0)/norm(x0), norm(X.value - x_spg), norm(X.value - x_pr) #, sum(Comp_pg), sum(Comp_spg) 

end