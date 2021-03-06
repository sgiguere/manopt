function M = grassmannfactory(n, p, k)
% Returns a manifold struct to optimize over the space of vector subspaces.
%
% function M = grassmannfactory(n, p)
% function M = grassmannfactory(n, p, k)
%
% Grassmann manifold: each point on this manifold is a collection of k
% vector subspaces of dimension p embedded in R^n.
%
% The metric is obtained by making the Grassmannian a Riemannian quotient
% manifold of the Stiefel manifold, i.e., the manifold of orthonormal
% matrices, itself endowed with a metric by making it a Riemannian
% submanifold of the Euclidean space, endowed with the usual inner product.
% In short: it is the usual metric used in most cases.
% 
% This structure deals with matrices X of size n x p x k (or n x p if
% k = 1, which is the default) such that each n x p matrix is orthonormal,
% i.e., X'*X = eye(p) if k = 1, or X(:, :, i)' * X(:, :, i) = eye(p) for
% i = 1 : k if k > 1. Each n x p matrix is a numerical representation of
% the vector subspace its columns span.
%
% By default, k = 1.
%
% See also: stiefelfactory

% This file is part of Manopt: www.manopt.org.
% Original author: Nicolas Boumal, Dec. 30, 2012.
% Contributors: 
% Change log: 
%   March 22, 2013 (NB) : implemented geodesic distance (needs checking)
%   April 17, 2013 (NB) : retraction changed to the polar decomposition, so
%                         that the vector transport is now correct, in the
%                         sense that it is compatible with the retraction,
%                         i.e., transporting a tangent vector G from U to V
%                         where V = Retr(U, H) will give Z, and
%                         transporting GQ from UQ to VQ will give ZQ: there
%                         is no dependence on the representation, which is
%                         as it should be. Notice that the polar
%                         factorization requires an SVD whereas the qfactor
%                         retraction requires a QR decomposition, which is
%                         cheaper. Hence, if the retraction happens to be a
%                         bottleneck in your application and you are not
%                         using vector transports, you may want to replace
%                         the retraction with a qfactor.

    assert(n >= p);
    
    if ~exist('k', 'var') || isempty(k)
        k = 1;
    end
    
    if k == 1
        M.name = @() sprintf('Grassmann manifold Gr(%d, %d)', n, p);
    elseif k > 1
        M.name = @() sprintf('Multi Grassmann manifold Gr(%d, %d)^%d', ...
                             n, p, k);
    else
        error('k must be an integer no less than 1.');
    end
    
    M.dim = @() k*p*(n-p);
    
    M.inner = @(x, d1, d2) d1(:).'*d2(:);
    
    M.norm = @(x, d) norm(d(:));
    
    M.dist = @distance;
    function d = distance(x, y)
        square_d = 0;
        XtY = manopt.tools.multiprod(manopt.tools.multitransp(x), y);
        for i = 1 : k
            cos_princ_angle = svd(XtY(:, :, i));
            % Two next instructions not necessary: the imaginary parts that
            % would appear if the cosines are not between -1 and 1 when
            % passed to the acos function would be very small, and would
            % thus vanish when the norm is taken.
            % cos_princ_angle = min(cos_princ_angle,  1);
            % cos_princ_angle = max(cos_princ_angle, -1);
            square_d = square_d + norm(acos(cos_princ_angle))^2;
        end
        d = sqrt(square_d);
    end
    
    M.typicaldist = @() sqrt(p*k);
    
    % TODO: this is projection on the horizontal space; make this clear in
    % the documentation that this is what is intended.
    M.proj = @projection;
    function Up = projection(X, U)
        
        XtU = manopt.tools.multiprod(manopt.tools.multitransp(X), U);
        Up = U - manopt.tools.multiprod(X, XtU);

    end
    
	M.egrad2rgrad = M.proj;
    
    M.retr = @retraction;
    function Y = retraction(X, U, t)
        if nargin < 3
            t = 1.0;
        end
        Y = X + t*U;
        for i = 1 : k
            % We do not need to worry about flipping signs of columns here,
            % since only the column space is important, not the actual
            % columns. Compare this with the Stiefel manifold.
            % [Q, unused] = qr(Y(:, :, i), 0); %#ok
            % Y(:, :, i) = Q;
            
            % Compute the polar factorization of Y = X+tU
            [u, s, v] = svd(Y, 'econ'); %#ok
            Y(:, :, i) = u*v';
        end
    end
    
    M.exp = @exponential;
    function Y = exponential(X, U, t)
        if nargin == 3
            tU = t*U;
        else
            tU = U;
        end
        Y = zeros(size(X));
        for i = 1 : k
            [u s v] = svd(tU(:, :, i), 0);
            cos_s = diag(cos(diag(s)));
            sin_s = diag(sin(diag(s)));
            Y(:, :, i) = X(:, :, i)*v*cos_s*v' + u*sin_s*v';
        end
    end

    M.hash = @(X) ['z' manopt.privatetools.hashmd5(X(:))];
    
    M.rand = @random;
    function X = random()
        X = zeros(n, p, k);
        for i = 1 : k
            % TODO: check that this is correct
            [Q, unused] = qr(randn(n, p), 0); %#ok
            X(:, :, i) = Q; %Q(:, 1:p);
%             X(:, :, i) = X(:, :, i)*(X(:, :, i)'*X(:, :, i))^-.5;
        end
    end
    
    M.randvec = @randomvec;
    function U = randomvec(X)
        U = projection(X, randn(n, p, k));
        for i = 1 : k
            U(:, :, i) = U(:, :, i) / norm(U(:, :, i), 'fro');
        end
        U = U / sqrt(k);
    end
    
    M.lincomb = @lincomb;
    
    M.zerovec = @(x) zeros(n, p, k);
    
    % This transport is compatible with the polar retraction.
    M.transp = @(x1, x2, d) projection(x2, d);

end

% Linear combination of tangent vectors
function d = lincomb(x, a1, d1, a2, d2) %#ok<INUSL>

    if nargin == 3
        d = a1*d1;
    elseif nargin == 5
        d = a1*d1 + a2*d2;
    else
        error('Bad use of grassmann.lincomb.');
    end

end
