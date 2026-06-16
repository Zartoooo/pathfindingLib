-- useless to make a whole file for that

-- returns the lenght between the start end the end
return function(Start: Vector3, End: Vector3)
    local v = Start - End;
    return v.x*v.x + v.y*v.y + v.z*v.z;
end