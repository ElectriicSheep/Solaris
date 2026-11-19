function phys = canGet(d, spec)
%CANGET  Read one signal from an 8-byte CAN payload (DBC semantics, as cantools).
%   phys = canGet(d, spec)   d 8x1 uint8, spec from bmsCanDb; returns the physical value (double)
    len = spec(2);
    pos = canBitPositions(spec);
    r = 0;
    for k = 0:len-1
        byte = floor(pos(k+1) / 8) + 1;  bit = mod(pos(k+1), 8);
        if bitget(d(byte), bit + 1), r = r + 2^k; end
    end
    if spec(4) ~= 0 && r >= 2^(len-1), r = r - 2^len; end
    phys = r * spec(5) + spec(6);
end
