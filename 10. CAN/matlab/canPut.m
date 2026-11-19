function d = canPut(d, spec, phys)
%CANPUT  Write one signal into an 8-byte CAN payload (DBC semantics, as cantools).
%   d    = canPut(d, spec, phys)
%   d    8x1 uint8 payload
%   spec [startBit length intel signed scale offset] from bmsCanDb
%   phys physical value; rounded to the signal resolution and saturated to its range
    len = spec(2);  signedSig = spec(4) ~= 0;
    r = round((double(phys) - spec(6)) / spec(5));
    if signedSig
        r = min(max(r, -2^(len-1)), 2^(len-1) - 1);
        if r < 0, r = r + 2^len; end                       % two's complement
    else
        r = min(max(r, 0), 2^len - 1);
    end
    raw = uint64(r);
    pos = canBitPositions(spec);                            % bit k of raw (k = 0 LSB) -> pos(k+1)
    for k = 0:len-1
        byte = floor(pos(k+1) / 8) + 1;  bit = mod(pos(k+1), 8);
        if bitget(raw, k + 1)
            d(byte) = bitset(d(byte), bit + 1);
        else
            d(byte) = bitset(d(byte), bit + 1, 0);
        end
    end
end
