#pragma once
#include <cmath>

struct Vec3 { float x, y, z; };
struct Quat { float x, y, z, w; };
struct Mat4 { float m[16]; };

inline Vec3 v3sub(Vec3 a, Vec3 b) { return {a.x-b.x, a.y-b.y, a.z-b.z}; }
inline float v3len(Vec3 a) { return sqrtf(a.x*a.x + a.y*a.y + a.z*a.z); }

inline Quat qmul(Quat a, Quat b) {
    return { a.w*b.x + a.x*b.w + a.y*b.z - a.z*b.y,
             a.w*b.y - a.x*b.z + a.y*b.w + a.z*b.x,
             a.w*b.z + a.x*b.y - a.y*b.x + a.z*b.w,
             a.w*b.w - a.x*b.x - a.y*b.y - a.z*b.z };
}
inline Quat qinv(Quat a) { return {-a.x, -a.y, -a.z, a.w}; }
inline Quat qnorm(Quat q) {
    float l = sqrtf(q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w);
    if (l < 1e-6f) return {0,0,0,1};
    return {q.x/l, q.y/l, q.z/l, q.w/l};
}

// Yaw-then-pitch, Unity Y-up/+Z-forward. Sign of Z is negative (q_y * q_x).
inline Quat lookAt(Vec3 from, Vec3 to) {
    Vec3 d = v3sub(to, from);
    float l = v3len(d);
    if (l < 1e-4f) return {0,0,0,1};
    d.x /= l; d.y /= l; d.z /= l;
    float yaw = atan2f(d.x, d.z);
    float pitch = -asinf(d.y);
    float cy = cosf(yaw*0.5f), sy = sinf(yaw*0.5f);
    float cp = cosf(pitch*0.5f), sp = sinf(pitch*0.5f);
    return qnorm({ sp*cy, sy*cp, -sy*sp, cy*cp });
}

inline Quat qslerp(Quat a, Quat b, float t) {
    float d = a.x*b.x + a.y*b.y + a.z*b.z + a.w*b.w;
    if (d < 0) { b = {-b.x,-b.y,-b.z,-b.w}; d = -d; }
    if (d > 0.9995f) return qnorm({ a.x+t*(b.x-a.x), a.y+t*(b.y-a.y), a.z+t*(b.z-a.z), a.w+t*(b.w-a.w) });
    float th = acosf(d), s = sinf(th);
    float w1 = sinf((1-t)*th)/s, w2 = sinf(t*th)/s;
    return { a.x*w1+b.x*w2, a.y*w1+b.y*w2, a.z*w1+b.z*w2, a.w*w1+b.w*w2 };
}

inline Mat4 trs(Quat q, Vec3 p, Vec3 s) {
    q = qnorm(q);
    if (s.x == 0) s.x = 1; if (s.y == 0) s.y = 1; if (s.z == 0) s.z = 1;
    float xx=q.x*q.x, yy=q.y*q.y, zz=q.z*q.z;
    float xy=q.x*q.y, xz=q.x*q.z, yz=q.y*q.z;
    float wx=q.w*q.x, wy=q.w*q.y, wz=q.w*q.z;
    Mat4 r{};
    r.m[0]=(1-2*(yy+zz))*s.x; r.m[1]=(2*(xy+wz))*s.x; r.m[2]=(2*(xz-wy))*s.x;
    r.m[4]=(2*(xy-wz))*s.y;   r.m[5]=(1-2*(xx+zz))*s.y; r.m[6]=(2*(yz+wx))*s.y;
    r.m[8]=(2*(xz+wy))*s.z;   r.m[9]=(2*(yz-wx))*s.z; r.m[10]=(1-2*(xx+yy))*s.z;
    r.m[12]=p.x; r.m[13]=p.y; r.m[14]=p.z; r.m[15]=1;
    return r;
}

inline Mat4 mmul(const Mat4& a, const Mat4& b) {
    Mat4 r{};
    for (int c = 0; c < 4; c++)
        for (int rw = 0; rw < 4; rw++) {
            float s = 0;
            for (int k = 0; k < 4; k++) s += a.m[k*4+rw] * b.m[c*4+k];
            r.m[c*4+rw] = s;
        }
    return r;
}

inline Vec3 mpoint(const Mat4& m, Vec3 p) {
    return { m.m[0]*p.x + m.m[4]*p.y + m.m[8]*p.z  + m.m[12],
             m.m[1]*p.x + m.m[5]*p.y + m.m[9]*p.z  + m.m[13],
             m.m[2]*p.x + m.m[6]*p.y + m.m[10]*p.z + m.m[14] };
}

// Column-major, Unity worldToCameraMatrix convention. Translation in [12..14].
inline bool worldToScreen(Vec3 w, const float* v, float* sx, float* sy, float W, float H) {
    float cw = v[3]*w.x + v[7]*w.y + v[11]*w.z + v[15];
    if (cw < 0.1f) return false;
    float cx = v[0]*w.x + v[4]*w.y + v[8]*w.z  + v[12];
    float cy = v[1]*w.x + v[5]*w.y + v[9]*w.z  + v[13];
    *sx = W*0.5f + (cx/cw)*(W*0.5f);
    *sy = H*0.5f - (cy/cw)*(H*0.5f);
    return true;
}
