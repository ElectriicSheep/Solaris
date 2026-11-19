function [sohq, sohr] = ecmSohFromCycles(P, efc, TC)
%ECMSOHFROMCYCLES SOHq and SOHr after efc equivalent full cycles of cycling at TC
% (deg C), from the placeholder degradation model in ecmParams (no calendar ageing).
%   SOHq = 1 - kQcyc * AF(T) * EFC,   SOHr = 1 / (1 + kRcyc * AF(T) * EFC)
D = P.deg;
AF = exp(-D.EaCyc / 8.314 * (1 ./ (TC + 273.15) - 1 / (P.plant.Tref + 273.15)));
sohq = max(1 - D.kQcyc .* AF .* efc, 0);
sohr = 1 ./ (1 + D.kRcyc .* AF .* efc);
end
