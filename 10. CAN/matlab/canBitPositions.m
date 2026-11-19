function pos = canBitPositions(spec)
%CANBITPOSITIONS  Payload bit index (0..63, byte*8 + bit) of each signal bit, LSB first.
%   Intel: the DBC start bit is the LSB and bits ascend.
%   Motorola: the DBC start bit is the MSB; moving towards the LSB, the next bit is
%   pos-1 within a byte, or pos+15 (next byte, bit 7) at a byte boundary.
    len = spec(2);  pos = zeros(64, 1);
    if spec(3) ~= 0
        pos(1:len) = spec(1) + (0:len-1)';
    else
        p = spec(1);  msbFirst = zeros(64, 1);
        for j = 1:len
            msbFirst(j) = p;
            if mod(p, 8) == 0, p = p + 15; else, p = p - 1; end
        end
        pos(1:len) = msbFirst(len:-1:1);
    end
end
