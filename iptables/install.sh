#!/usr/bin/env bash
# ==============================================================================
#  iptables-wizard 一键安装器（支持 curl | bash）
# ------------------------------------------------------------------------------
#  用法：
#    curl -fsSL https://example.com/install.sh | sudo bash    # 远程一键
#    sudo bash install.sh                                     # 本地执行
#    sudo bash install.sh --prefix /usr                       # 自定义前缀
#    sudo bash install.sh --with-deps                         # 顺便装 iptables
#    sudo bash install.sh --uninstall                         # 卸载
#    bash install.sh --check                                  # 只校验内嵌脚本
#    bash install.sh --version | --help
#
#  说明：
#    · 主脚本已 gzip+base64 内嵌在本文件中，无需联网即可安装
#    · 全程无交互（不会读 stdin），因此可以直接 curl | bash
#    · 安装位置：<prefix>/sbin/iptables-wizard，并在 <prefix>/bin 建同名软链
# ==============================================================================
set -euo pipefail

APP="iptables-wizard"
VERSION="1.1.0"
PAYLOAD_SHA256="8fbaaf549c0345daeebde597e268fdbf2d04d8b3decad4b74dee8cb8993344fc"
DEFAULT_PREFIX="/usr/local"

# ------------------------------------------------------------------------------
# 内嵌负载（gzip + base64），由 scripts/build-install.sh 自动生成，请勿手工编辑
# ------------------------------------------------------------------------------
PAYLOAD_B64='
H4sIAAAAAAACA+w7a1dT17bf8yvWiVgIPSEELT0HGnswxB5OEbiA9fQCzQjJBnINOzF7B2pJ7gAV
eSgEKwoqVLCg9EFQ6wN5yBj9KTZ77+RT/8Kdc639DAHsPX64Z4zLYCR7r8dc873mnGvl2J9cCSHu
6g7zLo4fIN0Boc92jHje6x8AJOGYGOiOcIJzMPxNIB4i5NdXhNRz3eEAT1zkXHeCFxMkP/9MGflJ
eng3uzmcn80omWVl5lru6j154WdCyIC7wl1RCcCc7/UPsZMmH+Su7P6+cw9fCHFXEGV6Q3p4Rf5+
WH5xPbs5LWUmct+P/r4zrtEBSOskxbi4EBZEjhehlefEnnBE5OKm5t93JhjgqgoiL0xJk8vy9GNp
/CUsKM1sSJNrME8aWZDXH8JDfmwKGtlDbncXHpTJl/LwCI7ZGZYXtnJjP8IABvBEBck9viqN35Uf
rCoL1wEgWxwRCSA6/QG+N8KR3PLa7zs3pM1HueUbUvrVb8Mj8Cy/GMmPpZXtB7nMMrTkNtblX27n
f5rPbmUY9JMa9FzmjbKbAejy7BuA4JKvf6tsLxLlpw0p/T1MbWiBD2X3ppx5gW/es/guvX4ppW/m
787khx/Aa1vb36mAx68pS88Z/I+Az+t3lNurTNIAP789n8ussEaYk92alVbnpM1NZXYt//AqoAEi
QEAucp7rhk/59hN5KiNt3YLn+mjwAqVcGl1jeOp8r64gQJey9VgXNEM9t/szoEjqm+raEUP4ItLY
FhBCaSKsG/HYfCjdGJXnVqW9OeQUSCBzL/t6gnGHrfGxLoobI9nXo9KNO7BMdm9RWp9HnFbGstso
THnkobQyhS33v5O374FUmMCzm1O4yspTBu0vFQR0DigBlsmTKwBK5V9+dkRe32aKCajIG2n552Up
PS/ffy5NTCFmk2tsMRTB1NP83R/kW1PZ3YXs1g0YqSxngMFsjb9qag6zACCsEYoGxWicSOsz0s3d
7PYKYjc8k19+jes9WM2+Wcy9uAPmkB+dAn0AK82NPZeHH9uOIUCQEeiPbkRCIhQlFa4Cw68Q+kjB
3zGS3VrJbn0r7aRz6QVpCkCMMz3Q5XcwLEEMiAnBBIsZi/zocu7x+FGTI2CepINZTBdOZlZkluoh
KwcGOCsVVNbvOFkMxMWkIEZjyTjHXuJcJBoIHTWxOxC8kIiZVmWylnZvofTfaW1cMBrnyCfyHZj6
8hSivj3N4DDtPAqCqiYmppvU6KjJYR7ojURMFFDfynSLaVJu47k8P61rEmwV8gR4vgnd5RKmntLi
GLgx4hwkH4HOKOsT0ptR8rU6BAwF9Ac1eGRPGp1i3kieXM3P3tXBZvcy8uxr5ek2M5ECA0KPSR+U
+xlp9zZxcWKwkCIXE4igg2QyANOQ3lzP7e1Kk0uAmrNORYWqNfOe+eF7ub0x4mwh9a3NLcCF75Tp
JzAG1Ci3McKmMmBSegPp3Vx//zuzTeBE4oySWDjG9QTCEZstzgVCUT5yidS1tHjsBdTaje4vfK1t
Dc1NHjvdlU0d3uamM/76hlaPvRi/TANP13k/P9fChpYMadNSGkdNI1vPNfra/F+cLADpiifgs2Lg
5P6h1QcMrTYNbWz+zH+modEHQwcCcVck2rtPXaHNNOFs3T/9DOk2z4lK23uJREj+4UJu4hnbTgCe
LdxDhkhHB3GKxE26ukgySd94UjJ0prnV6/N7mxubW2ucKeisJSnywQe0/xvob2q2dop9HG8jxOtv
9bX52j0lpZ1cR2V/aS02nW5urGctbtoCTfUNZ1lLVX+pOk0bUnuCjvL6P2v1+Zr0xirW+KWvsbH5
vN56Qp1+uvGcT288yYaerfvM19Repzd/xJq9X9YZUKvV+ef/3tBuAPgYWrmIwJkIqtXoqFWxr1WR
NjA1oWfgZEZEX71WX9HWE0bZesV45EMvAbOT76zLcy+Za1S2xzF0ePodbHu6b2EylDPXldt3bWI8
ECOlsXiYF3uI/Xh3J28nqN8M6ZS9lnBfh0G4JypLSUNTO2n3tZ7913WJSA+2lOXh3JtbEMBIY7sQ
GKE2gQKXOcgQ0I5KMghKoml9CjULW8pC4Tgf6OcQSb3T7kDdqzrlCnEDLj4B7hpGxzkxEedJJUBT
ySs9LpCO40IXOS508qUAoSwUEDlS+uHxM+R4e6mDUg6OJIUP5XZy6pRlkcIFxHiCs6Vstr44IE3A
DvRluil4QpCPIOnU29nhf+t/iz6kbGJYjHBlDoPgTl4lGQeifqbwAZU99fbOS1JSXgBASHQjy/Zx
jM4CnU8R8nb2Biy8f2r0wmHMpmaUerswa8wCEHTiYCDOo3IVn8isLvX23tL+mVw8XhRbNhMsGBac
3z8tzPdED14Q1eLXV/tnXRhQLSASDQYiJAYxFiGhQT+8BIFBbjuqcyDkKSkrI+6TxEnqzxOHAxrh
HdrJJ6QS3tHP4iiL8hcuX+IuGWprqfP62moqa2B0yoQNKamyo24fw+iaxbn55Zf5K2uQf0G0oIat
S2nMTWj6AymCmk+AKbvU6JINs7Wc9tjttu5AqJfzR3soT2gYtn1L/m5BunZXGl2F1EF6OkxaTute
CkydOEjuxStEYO++snYdaAkGBI5yAeIyG4YwGIygPuASmjSwzaQ1pLaWDq3zen0t7Q59KNMV1lpk
eLmDRXzacOSY07lvICcEgsioWDQSDl7yUyIphRq5FN1akxSonrecZupsYxlBdyCuih021D+RPgjW
/druru+M5BAFnEsb0aa88CMLUs3apVIA0V1u45U0Oi5PPIaU87fhmSotot2c1tK0mxD+mQilS5u8
KWw4EDHzgZjQFxX9SACn62uY93eTnkH4iCZE+MS0I0SEgSCMMHFkqK3d39CELKAzPCpH9g86c54O
QogHD2o+R50DXdE0CljZFxD8CZ4iYWIjfWdS1ewe+AdsY1prJV3dxS2zVDcDk6RXz4pNYiwaCIKZ
wifjkeMwW2RGZBEYMsYQnMvSh/w4qI+yIWXaey6bupmNEt09U/55m881tZutX15cPmB+yRBlw0Hg
WbnIDB7IT5l5g6YSSAicqu7mHUTdABCqfGNCuv9dbvdRfjaT25uF57fDj6wsbjjT5iEY7BJnnPjN
+3EwyveE4/26n1HfiV1OzygrW3bSwRIbcsnFdxmeNh7tj4ke6lxCXA8KuqrGyYOdB3jBIrrCTePT
AjtTKWcAzWztuORq6qoh+7CHBUwBi1sNfzBGhh4MjtGdwyPiBKhR8mGE2u35b/JVx5eXuso6fFxX
R5vQ5fi0BOYgJ3ABf5iPJUTGjGPEaDHYYWfskIZ37ERKz+fH0tLM1CF8qbITyEDg4QS6YQDFbE2L
+xFDc0BflHUH8kjTgA4GqMvoYozTzfEPAGUzqU1a+M74AJw3RzIQ4WuCQAdtyIKO1qRBX8zyUAE4
B1CJgT2gNxBuUpVmE3GQ7kRT7yMdU8sKrARKWG0YDIeI0QscT5TFYYjysWZLRyl3dzFxm1xSns1h
tXZ4Autkz68rW7SKe+sNyDy/+C2MgVe2KcIGvYeFSsz3YRirGRh/LoIFSOXptnI/Iy+N5bevssnS
VDqXyeRuLbJXiAdAs7AovfBEWhxmw0Az+RAX9wf7Q5ZwJ4BOHIIFInAx/AqSiyi5KNgIsByY+Tfw
86EoVYAgBhX0gQUFQ4GUHhYYFfxkOFatP6npMrow400tMBkDtf7qggGdKmjhkiBy/UExkixWPU9C
N/YFYqKzlxOT/dEQKGQ3l/yvKMgeojjoE4QkH0yK4X4OyE2qJSaHTeNskO0yNL8zImk9MiEg6/Kk
s6PO+Z8B5zddWqBi/lMhqGmjeWpDU8u59iTsmPgFKfr5utb6ZEurrxWaGpo+S7Y0t7Vrz/XN3s99
rc5zbb7WJKMzyQeAIlqk34cujftNK2nx1oF/QfNmapqICpds9f3D5z1gdtCI9czTQB2TWBRPnq1r
+49zvta6eh+AqW9oBUBJSOMc2kTVb5vmisFYMhGKJcPB/lgSZXHAkjQ5Mc0r76h0/rWrvIJ9JdVX
V3mSPRyyYvkhjNFW1IfTIBMfLnqYntMXfZOgyTH9hr2go6NGiAWCXA04KuarYFInndapGozJWQcL
XDVBA/wQVwELTGF/ydDFVGEwqDvhwuEX1QHU1xJmxdT5hqI8Z0nEqWeMUr/I0oyN15BXyJkXaq10
fU75+VF285nmxsaV2bXs1jThBsBNSAtb8t0NSBXkuSX5l9vy9Wvy+Aw4GmX7KhbhVeciiHGLcxE8
av4kQFhWgIkAskkCvrAv+Ihm6E5wK4Krs7usiK843FXs8yWFzsjR2e0qYuOdboPVrl77fkzewVKL
Wbi2HLXRIxdRLVedw+zzyElmq1VnooEePa+Y2YK16qarQVNt6HCAZV8lTQbgKHM6P9X8pPrtBLN0
MSCae+ys+iMgqWkPuf98IlXW2VlhvDmGaItLa6lKOT7VVtJwty7k2G8RgmYPbFeX599AiCa9fsnS
NbSQxWVmIbZ4gjftnxocQo53E1Mk/eu21XiNjZfuppYQvFQ3FTBMImBch9txSRmOJFWnPnA7aqHZ
U/Ipi/jKyuCNeDy05GByIppziRrx0iHVGjau0MVEor3E3vx5DdZFiiagB+bCFF6Nk3GJ8U1aeZp7
vlqwBl3hTF1DYxmwXUw5cCniPEU0t6Qvaaf9xeXC/BFbRXdS0sxP0s5tKf3KJf+ylh+bVO5d1c5Z
nlH/BJLDef870YFbo+XJdxMdxY9WM/9ffnSfMZ0x59YfgRTl5Wu2EIQ0wNru6NeWHSNyOJ5aiXP2
Bnl7b8kCmvwfK9sCIYN94QhnTYAiejCtiTxyqMALyL5ckLex7kiBnHDrJ5988olevXwHyLP/nsXx
fz2vI7m9GVB4dkINSRM7Z8azkTh3MRGOc/54NCoatUJaBvCda6hPgfw4MOQDEm+9vK6Wq0l+YTj3
aIQgNCIvXsnfnWErQ1CV23iV3d0DVwbJIz0YL6ncFwDSMyFmylhx6Q/5oUkQBVpnCEb7IUcIsWTY
bSemYxN0QrTueYzkNral9B0pfRPpnRiH/FN5/AR8aHZzigiQKwU5Iq3cyV9ZYwf/emGYuQR54Ufl
wWp2+3tlaQSPoV8/UMvGbV535V/d6Gajgj8GLkC85McDIwvPQPfpgWsUQ7YIhwmkhXHM/Nkzj0U8
DAx5Uiq4voIIrL39S39T3Vmfp8Pe1TlU+Wd3Z6qzrOMre1d5p8NoKoG93xUr3beQ5RSJ9FFT5Inb
YZUYCwf4GicjVC1FWrEPC0KiAHEdnHmEdUWkBQgxxTTlnZ0dfCTeVVFe4nKVFiuyMCRKdYGD9DLL
SmZOD9PVDTGzK209ojJcl+dW8w9+YAOwKlFFpPE5mMWuFrCNEoblrj+VX72Sp7+FBCC/O/Pb8GV0
0vR2gX6v4lz7GedfSHbzOvH+43PCQEpTS+QEPucmL+PFIro+WwTA17V5GxoIjnGrY/CBdiH4+0vy
+gq+A8LEo0LEg4sPSRkbTg8kjQ4HcZEqFbfRNTwGmV2Tro1K21vS09vSzjDjBuohKG9PNH6B6KcW
wA157jGjSN5IM5BsDIZzPy+rTMZsZn5DHn6cu7Kr3HqZfzgOnMIl6897KouniMf0gyGMMOhZKqzG
jlJ0cwFMSUlZRUWF9TAFDYQd/nhKyXv+K7XZVMTUGqwV6SLnPvXnTbwrSNhIsC8QF0j3JZHDOix9
85QMHRNS+sBGr7+usdHjNa8CYEFO0viYNP6EeNlADlfZ3SN0NmGFZV3eeK6Aa+iwgfF4ysaWB82g
vaAVtIFqBJ68gTWEwkLMPxgOiX2UXvNpXW2hRdefVw9+AMP0L9k34MtWlR+25KUdwFO+MSZl7plt
yRYLhPzxcG+fWCSVJWIg3suJrCRbeFJIUwnjrJANNZ0XsvgPjwxPFcZ/BsrHy430GL7wkNBOSou6
CFMCY3iJ7OYKWj09P1Q3F3ZjiRq7rZ/jE7ChDR565FllJqOq6o8ceWJEDUR0Owh8CuY33A9Zmlfk
zNrOti3zNQiKBz1uMh+Y2g+HcWIfjJNqiMBucqn3pSamwHzZuSo+72bY9UVbbyIQD+nHgMb+VeR0
UI+ua1lwzcUhR9APBMGwpPQG3dC1ignbQ9dXWLRKT8v4niixs8NBcBFgm9nNbSa5A04JWYteaTVF
3G6kMsyHRX8oHBcs0g2p9dwQq+caF6kor4xLVim7JTYN4cFCSr1h1H8BwBJnDGeErPcyWEG4rz8a
Ih9XVhYZoB8UqTUpQLShpd2jl3gc+FqN71qlxhbiRC4o+gcDQI+QiMWicVMApjPZOQhbjLMRN999
8Y5uWZal6E1Ah9ZuXlPv0exInn4IPGeOU9m5Ja3Pw7bIhMOu1ObHppTt+fyV3Sy0P7nCZK1eJUxP
4RVe9KywO7g9TBVIpUdXCwIOyANbPFsFdwY/IORv/hwr7PD4RbX23PaF1+/7Z0Nbexu+QkwqcKKf
lrfBWoN97OTbmFxLTLPhxTKdekGLLltDNCxtqqAKipQwwIg4DQngsYzO2iMEQXQs3YUVTa2j0qhk
0g8aausIQdbsVk/ZwrGBaj+mVJeKEkDpP4KCajMJ1X+EBsbdYkSwnoOoULEykYEXGTk+ZA6WmckO
wNMAeF+Duc4BPO6I8mbDcpgSkgEKuJzv8bMZ5cXTEr5HJEZtFd+k0R0p81p6etlRao53eQazKJAI
1xsIXiJl6kVaJ3t3vFMYi2fzRt5SIDlDWQ8Vnn4ahMIzXvCytjMBLtDZE0aeWWPw3jgXI86LPlL6
VbEzpM4KgYsPhINcqVXcJvvZL3FTZ3GhmwkyyV2/oGDwwODLvpxIYIV9zIl0WsOCMxAUwwNc0Z+T
FCrJ/pChBhh1gY8O8kaWc9QNGECYDwUi4MGLCpqPik71WI0LFcibR5ha2dSg1Co+IEkdeCRNhjhB
muqkktL3c8TrdBL99xn0hBePE/z0drDFRC8mwjQOHHLXOI3rAbSVypo+qbsnvb1H7Ob7/xB6Kt+P
KPfncaq+u1quJFs22UItQd6ZTKIYx6zlxYNwU2vaxXmOtLOM/KDeQmfJBK9zSeyPwTN8gvb2XwBJ
xxwF9y7o7SvL4Q7BO6AwxRpFmKixhFpsirloqRY/+4mT3laikMz1ULdmo8fw5zLSm2Xc2Gkqh9vz
lbQ0Mw7xml5BZrUQvN9Lb+XnHl1T7t8xtnrIqca2YDdnv3iRNnZyY8/ZD3akmWkI/djPczRCDbXt
LGcMLSV/nFr1Eu/OZWlzE0vgO1vSk5tEBch+yoUZv/TqmTz7Rtq5whI/bJl+oP4yZ28RtRzDkfl3
5pf2wwxnP6msPlmJPwugxSxnL/vWCYEH7Ub+/lAwGDMv9D/lfXtXVEe69/98ipoODHS0bW6aREPO
cdRMfE+iHjUzZ5aTcIBuYo/QzdCNJhHOwigKikgSr4gmGm8TL2B0IoLoWuejJN1N89d8hfe5VNWu
2rt2d2N0nLyvmVHYu3bd66nn+nvssjWBftSE3tw8Feb1HXNtyAA5za2DR+u8/cgXjK8ObH+dr+/Q
lDJTHaxqLtZZw1tXbioCRdkRxpyOdUrMK09rMvtEBBael1wYk4tBU2pfski4dPqb4hnUeWjdPg2e
aB2r9e2VMVxpMBLJI4qCI4SYoMkIIXWz/0bEsmZN9sVOmxv54LGnqDSwu1scPcuHLz+HJ4w3NYtL
Jil1b1Zl8THOjo5rEvVGQ/WRIEVCjsTo9TqlonfuQ1mtMSqz7XVlGl+Hjfv2qyEt8TgsByYZhEWz
gurb0/eL03c4ABZXc3QSpo2WJfYn+NPbm0jE3nvvgw927Vqzv5XnD8/85G3Wf6BoefIqawm0kq44
PsayMpC85XMPC8NfFeZPoeLu2Hzx/AzHHAJxhIaye5M9PSCCdO1DXwLRk0Wl2PLwFGrqvjxeunuj
MH0LKoQWl4e/IPlojBV6xoeJVBbnp23XpubGpuYa5OHaOb6nnbg42l5Qc6wp55dWOWQn9joMzSad
krOGKqwdKpVPxgyWHs0Unh7BjZfNJTLsVadEaH2FdQtY7a40vswhE0YBDKvq/lTXW5eI1b1X90Hd
LpIb2+zuyd7Bwc0OUQSSJbt6ZKY7lPCzTL2OZepul9CdRnNjYMqAOzrQJWKS82OlExQV75jxSbb6
SQhXLbmOVA9KAqtqGxrMT1eJpihc4+LTjv5PsqgaJyJleqH42M3uEI9mU3fRMZDLyA6oBdNBq8uX
LiwvnOeV89aFZ7QbpsBcbXNYrGABamgG7ZmRkOKno195zvnQzxBHZIxkEBGrFmI18PJduLm0cFeZ
o8c8VZzhCK0G1CjaRHF6TLs98wDhC4v3djimdvsoqC/Yhieka6CfPaZRZTvQb4iPvNtcDPR+4ERe
q4dfexNrswO98EPHgX2i/iAtoKhtGqrHXcR+2LUN1jdlLvnytdHlBR0cEr9pI2GE3JsjUjZ6IRw8
R0Hkn10pHppBS142u7cdlUg2C09P2KXRJ2Bm9yZIOMF/Y7vLsBRcBUhmsqQ9DTT6+MdYSMTVLDQP
4Xxn8RkIYXjM+smdQMB/Uc1qeVIxNUFhfLANSECAxvD/iXZys/7EJ6TLHlHbuUxP5kCyv6G2KdrW
FsFXEbMbztp8pquV9tPZmSyQiVxPus85P9i4np1Wnh02mK15fX08XsVsBbpAmmle3ebmSNDnh97V
Cekcz3EkHCZTQ6rlrTt27/n3j2BPxnaxYtplQWzy7++WoXqlgycrk6e92SXQ7nrxcn5urHjpyvLX
Tzn4AO5fKWMMLxTPoCVWxv2QanHp8F2+oLwAnVaB9bJecayGIjpIrUdhG+qn7R/uVj9SmAHucDt2
RA50Bd+XJ1GeG0xPipwOlQ+TNZGmUsJB40z3F/ut7khjiE8FNOr5KEvXZHxoeidHYjvYE1dEyBFU
Dp4Lvvba68J0FcXC0o+Pisv5CS/Mvn9ctZrCsNIbZQ/4jx4cXLLqZ3nD2q6oyqkjEvC2Id4QLz84
wgPpnHsbu6h/F1By6E69GcrxmrBwJDDa7AqKi3xt0kuGxgDmTk5ofu4ui5pwBdYk09mB/mQ7UlyQ
j4D62O7mfdIY0YfGCKKbTJijegFT3XbXN8lWYn3oMwzUPEH0FE8xvv6Lcp0vp7VlRsDrO9KKoThW
pzsecLPlO59NL8giur5GyUUCiYwX7+KUMI9QfLRQOP4tv+ITjtLX+R+Kd68Wjx/HMo/uw/xC+eVz
wFCclYyDNGx5Y99Y3dg91ksZWH6pSwz1mR2BpZ0fVWFdcJ30pz631WFIAoEn2Gl6iMPvv7ddzeHJ
n3yO2drnc7/YZPmzwwMZASjtevDgA797vfH1Zi9ckMpua7NsgPVU8qBmdOEYtYnaxhpltm6Kik17
O2A70jpOcUgGh23AsvLtgFEeFrQNz43aXsBjU73/I+Ifc13xqG7Rfi/rs5x34xTr+gnG6MbtF6vF
ThH5bURsW00dj0qtgNqqrpp5S8SjrKfgSuWz1eL3YbXpcPQs/vfndGS1+J3YxOVWi226XDr5aU7+
MqRnsDmKnh0YkXL1vGtKGtIDvYN9++CU7xF/zn0UN0J0zQb/pJvbQO0YLbREBce8QDuOFtBhGGuO
WrPXQM8Ga6PU4IqmNzC55qwG/lQ7za+J1qiiISpqZ2nhaOn4F7IAV5Poy2X/bT06Na9e/9EqqO5P
VnVW2ewKymKoBZT4wFXCWw5aCnmPwyITSwOswwGHDpyYAakDZ+XjEEasZbu8uOGDVMa7iLlYlEq1
RQrjI6Vnx4oL10hnOVU4+gCdMWZO5ee+l8BN4yOSij47Xzw/gwBITw6jamh6mEGfkHKqizLdkaP1
kXVT8FNp8Q6pOG6FQDoxmlNh5H5+/rYgfKe48LziddUyAEdWDfuwdG+WK2Vdidi9fRd8uXv3+/T9
zv9Ah6uxx8V7xzlwojiGXkGBSGeuTkJoXbllBjijuoHNBvo1tKbnUyuULY8F2zWhaUMZv1+WeLED
PqE3tHTh4tP80xPUCVU+PKhbfdTGy2fFuRtB43E+iY7veKn938nLg0PaHF/xEvu/wldIfuLsbcRY
Obi1zszG2RnJPQXs5G3dyDlzT7O5GG6cWAwPTAzIXGeyPyv1eMK+LgP1hk/0yH0juLLB4+yiwRFj
4LDiMC7yXixMTixPD/88PMlKhp+Hv4TdVzq8iNyGUgDDq6UzFwJ+tC8e1q/SH+nREhfMaL34PiQy
7VJXL0mXPFVO/D5c/H37RUS7yKJWvsH2ao3qQkdHit/ORYhnaxgghJRYf1SZLMLMqaif91CqHv2g
gAOnKlr7mUOklicnYKNT30wXgqhDZxWEKEAz0LGjhWvH+Nefhm/oELXfGIHb52Gb3FiamEUdLim3
hAyvFD4npH88+SYiPnM7RQltXlQfD/QlGLxAiM1bfrd147b2d3du37Z7y7bNbelMGg5Esl8atv1f
aovLZ7ppbQ/hvldtDuWpcQMxjgYw+sb01OmJ8k2Tb0ZMG2l+4To7onrQjMdvIXDX4qI6tt70qbDK
XzwxZg9cw/QEBr1dcF86rbz2HjUczV2lo56N6jXBB6R460rh0jnpYKc4h14pBvaiGJjqk04rIt2N
Wqh0Doa6Tw2mXZo11a9wy5uyIruqxbOfZeO9mQSQynjtwV7ttiYjgZFMR/B5pAox0ey2oMrYZytE
QgwWN5z/Rskh9iijSsJD+vvc8oVJLfF5YpvP+hDmFEJ73XCrsEcQ2JuMzOk24JtwoY596J1ez0uD
Gw3fVNoEYAasltla3L383LzZl4jlTEOKDp/XW+AyxTaYpCviNl4cndSGTXlGCMJWGp5gyl/ZrWdi
vL74Dkj3Iu0zKW88RpLVELrot050SAOqKIJEO9NmLJ0m0vKmXT4d5ms8F3fP44UyelaZdMeLP1wp
To8hgiF1RrtdRAwLjsTPIaWKdJ95/KPJ4GA9o2cLo7PwUKtWGQ8WvWbnT2Pww9xw4fo5fug2GRsm
qDLnL3gmaK7dJ+y3vy1PWGlJrGvbs6yrj3F9FiasibYvkNHiuW9ldxJya7HXPTqa+q3flo2Kd0qm
z7dRCGnY3CjFuRFYLdXeOPP0HJbBGMHVbBov4g+amD3KdQo3HDHXLeFKMRj3+HGpCotrxWxcaV15
xWV3Tj+GraX0YjwZhQu3oL3CtSMYKHpvXKP/spUI+aGROygEAs2++LA4cb1079nyuXuMKMoChRa3
NHFlmFyeKewfDcaYMiCmackTaStk4dTZ4o+jkQ1+Lsned2H+cbhO7k3md8HyLIIiJ+/ZLrxneQLV
9PHk4VVqSzg78Ncu+InncIMCEsBqkNlQK4brxaulr2OHpIQ/vRuwXIcU/C9fQdkycBKT48W712EF
lyaPiq079q/zTCL7W4XUEAyPi/3rgOE6WTxxozj6vTK4K09h4whXOyPr3FNi2+tlJytNkK/KkNkx
quNtg4OV6liiFzgPvNk0wA7SCL3zsBBtSjymtIP1x/wZ4eDieQF2Tg5Ho8+oH+RplhrwB7eKRxB1
Tputfx7+whMkF07mn0wxPRI2sb8LtLx47qZHzukmhuOTPIDsKu7nvmRC/FZ09wxk9yYTEUWRJOCx
TZS4RT3OitTmeYm5bLwsOZdk5dEP3KnK9BvKFc/OmlTbpsEM7RwYMJRmdz2O0WSkUQxqg1V9dhko
VZV39fO6jZb1DeU+q0HqXcbdrjAljtLmhYT4fPZk8IwzwY54MVkSCI/+9QO/oaAsF+rkmcLIYRKX
7ZlIdu3NiHrX6Mgkxq8NwXk05E6F62q6MH8GVqOeBCCl+6S+eLpPlt+0Chk7KGOPeVzCsJhwWeTR
Hv1g3/ZjDuREzzc7WrFmr2wY5yBXZ5riLe+eh23nbtVy+Y6GtYqqvnJAiQGlaPnpkRpANbludEip
JjFFCr360sdcLX8saU6OciY3alUbQRWUHZCOa2ZRrRnSygN2M6O2fS6FrcpNgeqO2I6PytNG22fL
OtSi5TaKekDShet9q7lt3pNhFNAWo4TN1iJyvvPwx2LpTKyvA/g5EVN+i14k9FrbidEKA7DPNYt/
ftnPE3GN3rKvqLM3UpzSapoNfg34yuRY2V+5wj7emHi4V9Bh2ZvQHlNgp4xhkV1mVwlcB82hdXak
08n+MKQCUjjb0qmpSvcU1JVykvjBCzTkKkfMuzqg7LkW0IkBPBQV3Go5sdVfCZKeZqsKyRqVE2hc
Fckz32LWJe9+f1GyYbf6CkJ30TGXbkxX/QRyttb8iBNNWNeee4rWmV85jpNrTt6w5iS4o/3f4Jo3
Wu2QK62OVo24l9VGiQQhfnl4rHjib8aWekdEDM/8rg22X0+Xz83Ru1i7TM+epqjQGg8EqiewU8/h
plm9zvRtEMHXLfxasn0b/K9b1Wtcug2Br9fqtmF/B1+vixqauuDrN/i1PNqBthsHI5GongALyI79
5s99WzwzyriSQEKyPUm4NJocbkOvTM1lZ0t5wR0girc/lTzwS8md0UsnuSuOj5Wu3FIJlLwkSWg2
IlMi60BeCtEzY3pk0htpMde0yzKFO2u0aCCKpVydZQ+PK+s3GsbDq7JIoJk7apTN3WwaD//eooxS
y3MFdXOlm6Mhn1h0UfKmjFT17ZPCk1Nmzq3YLlwfpccpXDtJObTGqiGd7N+2dPHLwuQdnhiMcEC/
1YGedF94JRYt1eIpZ4LCu4qsA5weCiamsHjGVdW/PoHVDiByR25wkVmvEBlp3MTWK6SUI0GSW0GV
YtQRqc1hwgzgeFl1siFIobU1w/Kn8G0h36YpjM4WRn7ML5yFS7Fw4Zbhn+dwrHQb+6Vfjf9C8Pcm
uO+8lvT283lv2m3hIgJXiOTGUTysJ28EehLcvEBaSs++FK2NSrowPdoMNYKHs+uzHwnjlYjts8SG
NNbr8kpNbRH1Gr4z0Z/pG9y6rQ3RNdvqjaCU1kbLE85oMtGbzH5SXc0hFUoTlmPWfv1XsmFEefEd
2N/Rk0qQQ297ti/ZZQPowAPyFYvHY/H1Qwifg2o2MgUr/28s43AAp4gRfkfQ6wj3uaphz/rVH/GP
0ddrgx+RlzE2kVI1x+Or42JIMwfpNsLX6c/V1a1/3QP4rT2YNptx1EwwOE2Nr1HJdzCsH+R49fvb
bWLd2rUtaxEfx/+ZAmvARhmvYf3rfjDgXtWr1157ff2QOnH0WW/Ffnk96+WeyU6p/vWW759ni7Z9
y3lZU33BRU31MSxSRyIBs92f7E59KjImgnuf0nOYqlkojKNM9dXVxV+XHlf4KUca0FjxQ5yg+Osa
HZFL4CuYmjjHBjMmP9RnTI0EivXhxDrmi4eAN2L9mnq5YzK8XahKEw6n9mCm6l2Roblv1LOeoVlv
XuuYcznZA2lMswY9qbGB/XnQPsMqbyH5xhx181DZbqlPrL6ph9DBluZg/1whqKPXUAvNvOPNI3CD
wk3xZiNwjm82rm5tbaEfGhvXv9nU2IjOM+yFQFHzxW8m83Pf86c1mkq0d2XQ3ak8sbBxt+BU92TE
3lQ1x7yaQ9eTcdACYLhSzsOoJpT75B20nox30tS7t+W7vakhiZhl8VsKb8XoXkR/HPF30/rUcVib
5Ap5oRqFe1eLo49gxsXWHShAXLrMcQwXFoATLZ7zIqspRK6rJ5VM5+CgW2uBHjk4D/Bh+6bt27Zt
2bR76/ZtHuoFo5pDoQCQKQdb4au6OvG6xoOdu4EqkRmEWJDb6OnXhE8wKqMnjh+HLRR7qxG5/dL4
4eLoJPy+/i3cTjUd2X3tCg+KXKrVAy+RRiDtSGH4iZd1hBNpAM3SaTaadfqRFhyV2A9CZCqZNcKN
EM0NH4m3RQtFzsq9Zeb20FkwSFFNSSqgJv9h3I/N7I/HRVxuJ/WAtrnasL57lBJcICaAsRfKZL/Y
r3dqcMPIkHued+Z+KSJ8lDOzwsfrYyjM0aYY+nl4uHj3u6Ur92A2809PULgsHPV/PDnlnXH5Gx59
bpYnr7ahgaeMYpm8rUrNl55dXlq4C3NZvHOFFx9NWjMzDFrBwk8kuK+NjSO9u+lb2hOpPo18yHsi
1fcr3RF6/eWF++JXnyfvuVa/aU3zmpY1rbToTY1r6L/4my954RlTAE3Ql48gAKgCZ9eXEDKzHX19
PZ/xmUGxyI4668/kMnKNOSwUlzjb38UpddDYlkEa1xohJF0ggvDLWs/QGOvAxOfJtoaw6Cxe61xm
KKIjnKF2jnBWs9QYoSDetHrHxBLrXdXWEMuSwRCeR0xYLxnRirfWat+tpT7sFb0DPbkUkUAZIJbV
Ma5cmxaQ1DdGHJlXSofSMj2nafD3slfNDzSlfop4pakeVfYvlCGGppZfKKMGPMYyNIvadAEc1y/V
4xmijVuPd3ZWxlJQ7lyQ8TEJz+xTVKKNj/Hny1fmC/OnGBnlpSj0pOuR0jB5DhcVjRcy8Ex9SUmC
4oIDKKpU2HHjwAtg0njKxu5s1lbSzR5aunGo7DcOPZ1qadMHyHf0pdKfhI3R0sJBS2hQkp9hu2Gf
OrRv0orz6AegEUu3TygXidEtu3Zv/N37W3e9t2Xz6p1b3t+4e8vm8BrfdNR48fLSxAx6iJ28AtX1
ZMqYiN4yP7cy2pMBqIusf+QrzHnvy1TVZGsE7ZTyODvsrEZU1Eh8feoLCiUfe8U6w8HmKAp6TJDx
hKsinjJwsJWLwD3nLLA2Kvh9V28fBxNblhXvXSKZ/syyqtArtOh09qTQtch7+aZ82ZPJ9KF3kPfm
LfkGGeHO/oFcEiSLLkP109TIve0ayOYyvS9YJSQVTYZyyJo76zLrzSSSml/JZfhGw8tM3mOaROON
mCI4EKnhIy+E2oNYgcYj9PxgTMpk+r8YZIddCcq6G4VGNTEHhmF4rGelZIOFkw/Yp6Z49nHxxJ3C
qUeFoyOIIqS4tH88uQg7fPn0hTzG752A8lwPZmsfOVS6N4dm2Cu3ve3753SEPcY9PowDLcUeDKGO
i4EE/t2Zye39CPgyeKbm0Z/AGFkGea2vXj1kXsp00+PdjjXC/JmPsHrfI2zLAXvF3Sqc+r50eBGk
ZOHvnuEVoB3htbAjr3l9GyB/VoYzV64hphaGeWRBOwdoT/HS9eL8JLOGSF3OXED33DaRX1gg/z+o
wGRlzMqMubH2lulKZq7H8VuYr2OP9jrkOwyXgx8pjsy3JJqNcVVmXYdYFT4IqYi9bpnpUyzKxx+b
SyzZFlw92UtaU+Mxted/yK271pp66a21HrrVbdeKIzQ/Qm4xjiDywHQe2beT1wzOi4FOIA/K6ELx
7N3Ck2EJd0R3YeUBEmPaZjOtjjQN2T7t8ZoNR3Kg1vxqHoPpJI63zyfZ2H7i+cVvGVeBR/3z8KQ5
cPTtn3nssck8ARhCQB7cNWjCoUBPTA/kx68gbRHBOJCrLOFHTk6Unk0v3ZKsg0dyaCZrCje+gBUs
Hn4AV3dh9EeqizvCuHTF48d/Hh43z9HPwycRSG10sjDyKL/4tWSfTCuK4VKeXzi5dOTH0o1DDCm1
Mh9y/tMJJ2OfHYejvLdTAap47VjxwS02fcHthBEDT5/l5yfQ+gPzMHO0MHqbT70WiqxjhAcSLgh0
vxzoRGr2AJ36aR4jQWLZ5iKDPpGNKKBve6BAZMoRlrThrAQJ6HNVksJcw9iFVViH5cHqb8MT935B
U7oOvTxyPv1ntE2fUWv2pG+x5LShOFc8ZKCUUMfQkEd7Up5vyRtakX9YD52wlddD+0wCpHHKrYUR
03dUoUyOS59xIEYzjzhU5y2ZtBw9yQhVDQ40P4koFkjyhiEMENxfNs8Tzuu0OHgdU6gxOJ6gxFMF
3yOvU/hfBD4sjp7lL+XV7FabOG7lwD3aohddqynkJbmBUSrUU7rvNoTdGjwml2YYCCouF9Er7+5Q
KDWluav5uRNL88/K3h2OK6IrxXcE/Mv4aJ52ORpIiYnWHlibBs/wE+GnEc6zqR4at1LUrxx3Xhty
KamGGtfopSoMrmRu0LwLoBa8S5x3ASqrT1yH75aHp0rPjpUePSheelacnufsDnwfyBgh6kJp/HDh
4kPDhv5Cab8VKlmGxFdDzc118ZRAjqgAty6MLnhauYrKImGriCwOr9o2/DUYqHQrJqCpviEXYTT3
kI/gAUewPD3MhI0hFZANoP1jhid61ExLsr7wBqe2pBLJKT9JQIugNZh6/CeW+6wvSSscw6xmIBrj
8vSkelM5Aq/Af5sa49kk7MiEBSxlTxJ3bZR1F/AF6nHjSze/QvJ+/gcagCg+/L44y1vdHDYK6T4I
hlBlz0se+V+I7fYGJzuCrQtcwPtf6K4bSgTXkmllE14VF+cKIw9Kh05rolFNbI4b66xXeHHwcHjI
uScpHIqsqgDQmIK4vjYhynAsFDCA1OvRA6BqKziSz9Fh47SuZBK2bvvDxve3blarWHHYqjwDyry0
ofq6ZQbnecfHqYkcLzz+kTunK2GPbxBc9D5U+irnJjT0k3D7Pv+uS6FVvfoNxe1W2EIbgqi/ZWfX
7oN/Bs2h6rmxNXb2DJVVwVZDajyoWNHb8Sm86P9MAJnM+q5aT67kSCMlDbswcNkI5dNJmJUx8vbS
9+dYt0P0Fa/udcD3YNtlPuWP0Ot0erhw7WZh9lJp5gwQ6eKZWaigNeINwnf7a3OTy83loGk11hZD
K2xlSNu9oINl6jDHVng2snxlAXPwnZkt3D3nrk91uFydNL7ytTFTPLEAlzWyw2qjFibHl+4vyN07
ex/HdvRk8dRXaFZeERYlzhzxPHKHxWKECAT74nc7P9y9BX7vZ+CJaumWtXMDx2vUEs6GJDa+JmV+
rO0ywroHeUOjRqhLHuTy10+Xb2Cmi/yT84WR0cL44+WRk/LIOM/wVvlhU9n5cRHPbVv+KI0g1Uxg
jNkUtpjiboN6Y3tTOcLIIpwXtWUiBjku2+Xml9RldOsyiZlcBMVZTjJKzJQ6NXDS4eiWfkRUPGvr
4w4/O8tcBQohJ8aWF74szVwHIdXLJAePCpMnMUEZIuU9hJNGOP3jDEYDDGlh9NvlCzJyAGHBRs+a
cVClm9/BW686rbC3kU+JRPBZAwGncO8y7Ed2X8amJm/gTrorG0Hbx5FT+cceK8jWE18QoG3aen4T
g98Wln98AqGypo4oo9g4yOLAs1sYdk7MO65ToY3GNvrSLlOQF+0c3wv9RZ/vBUV4wQYLK8/bzvdW
GgLfbHyzMey7v/heuNH4Xs4Ys+7uSl1HtT1WUIAr623O1dt0Ry6sVefoduzcsnP7h7u3bvv9P2cZ
q50S+QHMzNadFjqir7FcJlbtrgnCGppcg896TFoCSu5gMxrKqxdfKc8QeQXDxVk6vMjuhM6blyrO
P5nKL1znDDml+dv5hcWlhVOCUqWoywhIyG1OECIKI4dlOmDgGa5eKlw7izlFvjxOFaJ+BwjM6ad4
iZOf1/KxcS8t0/Qt7C10EQ0ARy+IWlG6eQNh/RbvAKEpXJwtjs16CsVkrqO9P9lWv2fD4G/ffuej
wT21H+1p+Gjwv+tNZQINGngQoMtc3qcXsfBteLjK+OAfENy5G4Az/K34c22DiIo//7d4B30bS88u
5Ocvoub03uPgVOXnry0tXJBVedNFoGIcKG9TvmtnkfJRmEuN1kZBE3g7LH5bnL4DpJkpJpajRl1I
gPzd8+ilLL7DVx/3H0aYnzvOfWQAMubqylU95EzuQ/k71SpFnktB80rgL40b+SVFSCaSPUkN+a8d
qcLdqMwuuaO/F+bRbg0cISnxzfBJmEq5zShA0iY/pvvU3mAfqnCdwjhMrJe7iIyOAj+tJvARPgeW
VqPgoClvbqT4zaTMyDB1xMTLCfNWst2pqC4TqwrV/bTN2IFBIe1UHfEXCc5NtQ471bnrOJx1mhDW
GPdIe+dn7ZxLwYp6ao4yQk97FyKbB8P6WtT7DsQvCkZNuR1kqnGPIecYzqgBpDC2S7DLamHuxtKT
s7APGJpeLyGlwjsrA3Npiyw9vFp4coYxvzDG9NhDcnXH8EEaTDsj9mrdXuXUH14KnNgOTJwg0j0i
1tmB5KcZFdP1UXrqiwbEjOXWFNsO9oQYD12hsAeRy+Q6eipqQI3bmzcETIDYQ/xaXAJaxRnQCp0h
6HlEtuTbEfisDXYE/steEJyhB38n3TmLSGSI8R4q0CzfYwnJZonn6GU5eTJMbYByAI44mDAkoioO
WYQuvQoSBMW4ranK9bHGIRFL/hV2nROaUHYb+0emIcYizC8s5BfPOHLLebK0sjEaNejzz+jN1P6Q
ETfp2HTGAL170lzY0o1Dch9PHeGdjfWz4xRdjMqig3vHzarBG49Tq3StcvTbQG85FRB1o5LipqGB
uqRi4/Dnt9t4mWWMkVUdCLyFY/PKRDbaJP5HzyCOMLBfKDpoxdvFO7OYXogRYXGwfcpnmyZMhyB6
vO3SnTtqXvSFo9F1AmNXoUsUivRabKOIxzYLjlZzs0LywgXGzIPyRjarOlbIxjkLZ4xoXBEDk0zu
LMfYiBsySH6QWP3/Q52CjCvDVppH3+YbvtFADRKJ1Ei1Suf1uRc2oL1616YguLAWUTMw/8weIe4Q
9mWqtkHnvjJqiirTnb7V5QZ4Yeie+bmx/Nz3pSuYR9JC+gyft/H84lHp+mWmYeHvlkHyfDKFKDbX
7teUTly3Bnt+hjSAaNhndm1ygmUmFe9/vzCxYLp9RcIW3Wb0nveIytQZrxRRk0iAMRonOqS5O+iQ
RWEFzYfykPkf8yGLWiCSLIeZ4KsylSuJEC0W5BQlLCAXDEJreiWymQ9E+CWJZjxnvzDsxddVp8gG
vO/y6XuF6+cwNSuBxXhgD2cfF6+8nFAXRqOyJaHRMBRfl5BESjpLhuMxSp104Zv5pSvDysVJkjim
C6jUuH1BrFJxKFA8jn4GcTYghjbW4mzsj8lOoaGEoSVsfBW6W68Syre6MgqYqkwmtpn/Olgj+r4v
fqkLKOfukOrXOqvfnOnaB7SkcOpE4TqCjskJSPBjrP7Kdcp38Rha9sCbK0bm6AaMEzzKuZ4xF/nE
F5jx5i4wz48QZXnkwfK5uwYc8q8R8gYR55mo4WF1Ad70MS59Nrt3gwvqRr4+kOwMvm7VrxOdDtCy
td5rWrgNDmQxWSDTl0y/XOgw30w4ZFd+64d1NE/+8xt1pDNCG2GHkg3SFNCK535Uu/EimVWNchTf
LhNGMUEoTtwqnZyU/MCYHTTy/xbXGp5ciJ0gdf3ede/lFlKXeWdH4hNypXWyiYx3ajkfUF0qsCOO
0+xFYsj0dL4oG3qIYTb0gzFV/MD03aNZMR7TctvCKQPBu6MsgmKkF2Trr7MMPqr6yL+UPm9U6RB9
7ymi0VOtMOs6SyRnQzGCEWQeGeXmUjFbpM7aA4c1kHDT9DD9Z7iXeeNdejJfmP1SVPI087JlXrle
GBmJBPKNvEgfMwvQqcycVO38VLmjAR8mK73Mox942KYvk5mD1EihEtxsikSUcX5WRazNNzkBR7zm
p+GrAg0/0/OFQ1OlRzNLp+/HKf3dA6CVaEwiBgTFN7gfHpzhMBo0JC1+Sd8q5oKYB3i4tDCNdirC
JacCJqQgxigzliAixF+7DxdOxIIiYG1IIPMUyAmTEyx3keP6UUPYNm4UY3jPY5aqQrzeYaqUIppO
BEVto1ec0gY7ZpV/HmsUJmJlroszSP3SxOg17SzQ8/WrctJboi0BOaK9knMsjP2LiKvl8jj88zMu
wOK0S96rM/kJq8fIxE0hLChzUOnAHrOmn2pBFAQvrSbWwUgXLNjIhMorJjYvg4i+GI/Yf4rDerV5
pit1pkLCZcUcezKAL31DmKRakRNGBHmLdZasZpvbW0aoOyH0PfOPbeXdgwi3nm8h5dmLG+t/Hwkf
oAI+QlG6Ad3lo/gbjtCE5jdm29HGmdHi5WloY/nCtfzc8dKzWZlOHPkambKEmXUZeDM3XHh6gvn4
SLgOnVI8lWauq2kfxTtnROJ8y5QZyrC7Et2dddLxd+/Mhl8bvIfKbXovvXz5UpL19/sPZjG5JIN/
/nUglcypLDB8W8BgaDrQr9yLpvOk0ZCNamk5fkW7NHyLVr05seB7u3fvCHXXku93mQVaW1vKbO/C
zGPY0uhkMPVwefoHQQh5CI+Xn5vATv069rKfHjrBhiTuX8X74l/7YCTCzkVQYVdl0EA6KXEaTLQF
fChQ+47gFTLTmFb4kR8W8tUSZydiQGw54k1NJIiA1nB0efgc+cocXZ46zYbilpbGdavXtrY0r17X
8sZbq5vfaGx6I4Dk8K95sFd8pL1Uvoi0o6u2UsjAWhgJZAjfTPs5G8U4/LnMWffNPRx6PP0sSz1B
Pk7nmGO5auniQyBUvzIKQO72aYKlLEsNjID4Xw9FMI+5jHJZGGFsCRyy8Jbx8Y868YhFPUgyDqEg
lk7+5d6s7hP2qg4hFuSZaZSmB90MZZWLeNoKdilho69OQyfjCSx9w9xJEJJ+ZWcnpWfBPBIk1oJM
k95H3kFOr5W/bhH1nf0x9MXpiHV/dLCpeai+6ljslIBPVwUjLl/AWax0rl/M/YzaCFr7wrF5WH5g
nZS69NvC7BHeLCrV8pgXucIeqstTpwqTE9LReG64eOeKI80frwsao+/9Tam3UEGzMM96V8Si+vqp
edLR3hJyzrVp7Plyodr+BeOc9jQ/NyYdVIkYLB9eDElxml+YKN69ZrqwKcvouJnKFG8mTndKJK2G
0TpKs4cxTnD0bHHiq+WpabKcYAARg3O5PCLY8udPpfq8ThGvCTyip59Cp6Qe7ehJO0fTFDv2y2N8
+c7yuYe4KSZmpdYfE1EqbWd+7jS7v6DShtDEviw+vMwxh5W2f6WN/bwHwNb+VDoQaAlwzfArc1Rf
vn1+af4m5zF/Sd4QHYn9Hemu5C+FATV76nSG4DQ3Ou0NZ7vAH/5+As7AL/eEIOO85Qjh1IpPgXgI
x10ynMh7MseYn1soTs9X5w7BZLEwcj8/fxu9CHhoH2zc9Z8fbtm5cfOW6vwcECWMkrex2R6Bb7iv
YciUrbaXB2a1KV29zToalGHGMVfm+9t/L8J96WVNax3T9OwyXPDF4Zu8HtXk7uEQBFxCoA6TR1WK
o5DQgH95zwM4CO0JmUEn6HSAb7Puty38NtXXnek/ALePK7UOFujJfOLKzrOW3+bgatwgnLnMfAl+
XqbTgZoEH2SImbKKz9FoxXNUnbSeJDEmARwZ63wJnKsSkuRKISR9kGhYD5u19SOEL7OM2qEwkUGD
ttYJ8Fgi5sxQOh+y/JFiyvAtcuRaSUogAIadph4aj9a/7vOPNhYFFV6nZ5AtO3lG53pA9825k/yc
vbyB0yiMnoMzGnBc0IqSBP0dWbp4r/jtMV5SjHYOU4NIRT0X95AYZL+do0wER5koM0qjZucog+vh
ISr9BllPSoKURg3QmlTf/lb4q10eVDfrL+o/bqqtD8QtaPKMji5EupFZnD3KyRP4ScSf3ZraPuBq
u41h6L02HWXqRTyZ64pzPWuQFfQnoVU0VqdUDjZTL955J1CPEkmcGIJO1ipH5B2EHC9610ZgN602
avXRBoWXI8XMJoDApaASxI1DYP5U39B6tfSRcFlOcX6+xhKqDqvhhNdweU7RG872Xbv1eMxKw8Zm
NOHd+AGMAZVAfIpPvz7JcU10kGQ6ZmGFJmsNQvD9eGnmELI307eY/nAKNf5GpLtEbP/n4m1Ji0gS
2brjHd2tiKL92QDtN5kdEWB1VqCTTXV3dCU9UoOPIn6961vNa5rWvbmmaU1jvLk1Uia8AZ0fT32n
wcE1bK5MZfLdMLAxKkyHGvZdEhJujZIl4WtfUDE9a6ttgH72ZwZySR+lIGyZ+MeJZHfHQE8urlBm
1m4QyU9TuaF6C9ffasOgbKyU5K7awyFU07ETSFau3C4cJdRxyn8uO6NyYo4FyDipXo26/KpX7ofJ
bNeI56eRdF3+s0nec5C6ISPOq3piYGpeyauBJy948isRrnIVVTL160oSRiUpq5Lncy0IIVdS8crw
it7G5eOfnzsO28pQ+Cg4R6BVxePHpUvT+LHC5JeS0Cj+QetV4D7YJbgIa5AM644kQZqPtumQJx55
XrADKC3A3wh1We0mjqpjwhkgvST3UI8bAyMsMTbLb2E5r1moqxh2/E+NOK6x3eiqOa2v4ryaKJA8
yXrxUfB4/CPQREScCTRdnJ3LPx5R0LdjES+WekUjVykpKWAxJeqz8Y+d/Y87P46XnxPf+AKyvxeo
bYt0KipbSpI+LB+XNuD5nb8Rx0OjURWnbxdmnxaOf4va3EtXhKlhmIImTaMJKwK5eTQA0DpxMl5W
+Pidv0Ohvv5C7cRiMNSYzHAIJGB3DBtYD32thOPl9VLDd2mYDc/pkfx/l24uYCTozHVraJ5vY00Z
59PN1fbXiwDl5iyfTD9WnwsKhBPl8CyaQY8cTFK4dhP1xk+m8vM3Yf/Dr/BQZZQds4cSriOuDivQ
7xC2Nt6bSleeAX7Tk9yf7BGtgRuIh+eBnK7FwNg4mtG/+sbDl4HbZvTo0neHli6et00P9y5jSILk
i6Z86W+7FeOiuqPvGlS6OFUdPm2YJrt7M1m2/ft98ElMZeUHMrLNb5AHQVOEvyiDHGhLzs3NTpjC
Xw4TaBx3Ieo6RV12fV1W/DR8Q0g9LiUL8eti8RUOwENcH5Kn1shDnO6yOGcSNj5H2tri+tz2Ag0m
VzN1y3zr/jR9Wiop2Xji1xUbiYgddeDN/NP0ecEWTFRBX73N0Wr+emjrk/d3LtWbBE4bBtDZkd0r
Yl0iQtcY9zzX1ReX44pXGNVzjkmP6BeMhwkJQ8oRM8aLy5wdfJxf+K50RcqKGJn7lOzs9Cv7x5Se
nS+cOpef/7Iw8UXhzFFGNl9aOFJYvF/4+uQrMYn4cOtR9UzmmpcVKJrsz6Y0gXhey0hYp51WktK9
v8lba/qWRO6fnMg/vbR05MdqsqPB3t3bkW0fSKOBK1HueFn2gJ+mvhWMZYWZA6aOKLCFCSa1UHTn
h+9v2dX+h9Yh3HcK02Vc95AhtIqnH2PGFQxNgAHer/6cmjw2ngzui68XLKNw286j+9wRs7xCMmWL
AhTxZp9A4g2msgrMIxbeab3NaqtKFkeXmPyWlbXV2IPyCxP8DW8ubxgkRBTmTxGMSXUWIRBNigtT
hdFZzkTPVnyundPTF57d5mbC58OyFBVmniDSiFzP+eJZqOpHBsjPz50oLS4unblAfgfuiFgr3ZxE
oSKjPffpVxjkqs3PrvjWhLLQb3BYmnqAIMnXWZehCT0sMv3JsBrWQolMTw++be/pYJtT0OKU/FQn
XQk28kZUdPUkO9KhvXihBik9GVb8azczId0g+PNb7mvUn2aAT9G9ccxlzArXbvuCZVsPF7t2v/SQ
0iHPPOJIQaY7S3+bXz73EMhQ8dJhYE51Mgk7ZxR01TexPjVq+JmKWMPCMRmL3N6dIsFN7KVdlmYp
3lBfdg85El+Z/ijq4I6zwpE74hpCuSxy1GlVkxm0qo4LLkQ2SUC8EZrlaAVkUS1rMlRjbQPrGQhd
aiMzpd1+TCEJOOVh5tht+METySGNO82Z0FVWrkkjJrJ635kgyk9MnjbxtqjH7tZbSD96ooMiJ8Y3
nZPeVkAQkQecnucrRqniEJZRxtaZ5IK3GmEu86N2GQoVmL4m5+SRLNDdq7cXsrrW0ercIDrbrNVs
snLjdrIIQm3HGkgSOdg6FJU/NZs/xVwPvZ/+vGZ/a6077LcuG6P/sZiyHnMsaxpfe/B3G3e9B8v+
wcbdm97b0/QRSxfWw2bXwxZ8GFZNq+uLta6H6z4K4dE5EXTnkBewZhJrHzkw7ncgOdjEpv/4cAec
iJ0qw5N3xoP0wJeGR7L5U1/AEZc0JSjUh59AYg6E5E8ZKd5iu2XM/5lZhM5EdPtT8ANf4oXJk/YZ
5E2UamsSIAiK7Oeacbauym7NQqdhr9m7WdEPZm8/h/eJARHb6yQIQZR/a0lQ0q1rTtR1RuGnrKBf
W7JIPkACxl/WZuUPWR+vqF12aP1TQxElfLFY7JVr8J0l1fuIXRfOM9WRRnS80NrMktnP18f+raqi
AdJrf0SfNDSkVq3SicGBYL3t2FUVroDCtSk2RsLDDzb+Vzvv2V0gE9D9IvHk2AJHLkHwTfHcTRAo
zN7gTWkxKfbJ8DGytKeMY+SZFOm2tHD7CFVXnizJ8Lpx+8JQ+1aK2VdGG8MdqAaxj/H6LHw+/hhm
Al6gBvzmicCXYWyCAbLng9jrduProUT3PU9aGLqe82oVoVuf9L/BW/eFY+yVvX293fPib1+TPfaR
dUPQ8aghqpIoHCmXRWqG5rlVdX+q661LxOreq/ugbhcuExRqi8QReDruDZAu2dqDuewQ3JUR5bwu
32LHxDsw6fBpqAZKMSPUMckDU/kgF0xFglywoE4J1uVX4oEtycA3N0HBLQyVUVj3IWzQEzJClQmD
FB9XwLn1ohI4YtUKc02z+zrMrKGGJrr1yvx9lyZmClcPAwmFqX/xHUhkuuC8VMCkNtxVNXNvdgu2
BtdjQfloBGUpyHSketoaRa/ImogvWz7cutmPDEsTTxuMt5bKr8hwO5cuSyh2YtkxzyJW3KTyLdp6
aHUwfLtfPSZsPQ+fM4ZpcdEXybQNB0+F/gDdvu6Nlb4b0b3QoBbGoRSx95H8hlunaJ+RQQxNjxJB
AfWvpHMNtm9CgnhfoKPvf22KyyiNoyMSWpFxYLZt2d2+cfMHW7cJ77QG+oxR+r0YpZ/qk97xIt3d
7nkSyAG1yx6qX8kBNZExU0kmBJo6472ZBJyneO1BRr6FcwlP+voznUl5H/UORcrCu3gzw2miBH3i
1xxK/yh/OUGIlRySMsop4dgXnQMRNcEiTph0C0EzhprcmNT7JtM538K5ilCcFm8Mc/G4n84P9E7C
8AqtQVX4tvknU5KF0jeY3mU43VlLGxvIrIjgnY9HCuNnFZWcMoqjpOHgtvX7SNSATvYNxVcx7rVr
9wPVm3E/Uq168gEtzDfF0Ukvd21NGV21BHEK10crTbBWRI8iQOn097LBU+eLOuenlVWyolrZ1zm4
9x00JdtmRt0Z+sA+0ZvKZqX3gIeCcTA7ZOTmrjaxleke5D82dLiwqSYz1zR1GhhKfAPspAMXy87C
PUQbka5jjQ0qnWIktuW8cICRAufE1AY5hUOnAwcUJ9rfkEbYivjzptKdwf1GAmX3mwgg3zrQVbZc
SQDTkdH8s3twPPJzx5cvXUWg7vmrpbEfUKPo1GzR8lNNXM2ru+HJ4ah444vSzdGXcMN3ZPd2Zjzf
qZVc8ho30uxi4IaX3lNs6QbpP8JSMFpDSQL136ZYeOnBwtLCNxElMWeyGNSZy33Wjl/oUkzTdakB
qi7WH42UP474qXpMwnAVV7xscBLjGnWDyLQm0wmvU3pT+5uQZglNx/2ydrByKUPHYgEbrc03ke+e
TNqB/qfZ/V3t9HPUcOmiB55FAdPt7k8OwtN0oqMHaEGUY5nVckYsu/O5U56lz7RAqi42qPpN/a3S
zaczuVgqDe97epKJqFBj9TdFJmpoyDVBhn+T/0+FqrjbK+yztCbA/sGpTKZxDRO+3cPyH166kzOB
ydL54kIs9CEVKMPquRM0C44aKt4z0j6VTXf0Zfdmcu1qb2hFLd7ene3dB+AvkOikQTrxSVICRu7a
3b512xBwflQSsfF3/E5uUF+xd/8oi3UfKFds+4e7sRy1ZpVzhs631R7EdjFQ/o/0c/cBDoinX5QI
yh9rBePysVMRw3hOzW7a/uG23SZgBLAo5LdsZgnNwmXb2YOBxIk2zKLV09Oe2SfvR3ofvLSNG5qR
E4xbugxg4cquah+AoexXo34g+7yqjSoSPihC383OX/vvdpxAOw9qORQNv6ldX81lrPXP04JyU4Hd
r7gLYBXlcOvEkNOCb/MEFbhdwjNQTGnE51xjJWfzKjBIRmU+OFrmyPsbNhwpCrNTMGhmeN3dMDOm
u1lgOlHEmDISnp+qIEH0OF5KtchMr3Rb0D4YASHdGoWjCYvycfUOvyI+eD2d+GPnCgyWeNh6Ol0L
aRgYI96F6dQxQgWRsmvjrovNI4HBAB/IXJJkmbCbOdGkdaWo0er3W9I0PG1yz3vw/+b/U8+KJjkv
qXSyLfLT6eFf6f+CWQurYB9/OgP8BI4cfrpXhe3X9/XpL/wU5I/vbd29xSuh1Z4HUp8Dg+vLvogL
vL/24B+27Ny1dfu2Iadv1f8+CjymmjcnO1MdaaFZD4btX7p3ZWnyaOHR9cLIo5UP58ysnoyZKg3h
y7BtbxwShi6MUGDoYKP+nOMM2YcMXsg7U9EhTCBskBifweVVSDra3eYleOdhPicDFN3hmqcloXDH
MNPbh5VF3F+3Yx6nbOQ8TJMTbFbyX2LkNdifOQDkI2JKUSgGNKOXMjLD6ElCQV++b1qQcnn5OPCb
Vnhk5PnzfbAW3pLXtHIuE2KdUrM7P3hDYXXrtBUR8SbcAgZ0g++Lt0DSs90XI6IRYdqHC8fmX6Yb
FcbRVXCi0isc4kMlBRWXExWNL5vs35/qsr2n6MX+VPKA5TElcTISlo+UkeXR8o0yUox4z9/UlTDY
hvfmLfUF6wdNL6q/Dv5n1KDDQbv90ZOlm4eMPbhBTlt5lytixLqGKnpeDWQ7PlGuIV0dOfH221u2
v1tTe3Djjh1DwqC14qfh00LSUC8TqkFDS0cwCramBqO9HpxBQGwYQ6ObZsxfy89/VXhySlIOKsgu
rmXUKFQKWRCxh7Wtg+mO3CBDEn8k60BbmdOb2Ofwqf08ddv9OX/20MkZoMRoW4ajt7io+SQNu6E+
zfQFEo9Sbh1UWFooO+PMIrMyTlegwJIsQBjqJNMJVaonAwfHXwo6JrM7USlmoXydCfineu2SWZU1
ve/I2dJ2eXqq/D8lzpd5O9n2XjkYthmVsXZRKXlm7W4y1Xx6qfT3s1xKqXXMP5yUcmkM4Ra41N5k
T2D+ZerK6TuFuXuF43+rqeHB5Bdl+CN8qW9UIybSEyDi3iW7Dhk+HvHSxXuFRdzZwrZcYnVfn8wv
TqtIHCrw/vbft7+79f0tQzV4oOCk9fqzvaFKJ0Mie9P6GJIHdm+ThJDfetQQBzoY2zsYi+FPUUEH
108L5JwNxvYPar1YlIPzIvJMe0c6QEmwD4N8DgfxoA3ieRqk7TmI+3xQ7tVB3o2DvNqDXXuTXfsG
ee8Nym01KNc4GkhJCkLTN9dVVuIpPU4Z/UzLybehIiRjqp9m4lJyCvnrQKo/2Y6sFBI0INFdufYD
Halce3agT0bvpNLwayLVTxbKsKnFcZOiSnMcqtc8GVFhXkM0m/I9zhJ9aaC3QAPN62NMojxNGE5l
VP0gS3qN9FMtUg/Yn/PeZPr4I3oDlEa+kAsRpReKguh3uDhRId8R3ZCvzAWLqsMq3/H6RUXQ3RYl
JN5CpqctLV63N0C58CoGU/mjwFT4PFLQ5WD8WOHelEloSo9mCk+P6JVmOUvV0y1qm22/G3mglScL
9qXZ8bHtW0IqloBXSQS+NEYIZH5hAtuThjk1PL2fPZ7jJW1tmZOXkOOu3uZEemxwQ6MM3Uqol//7
oaVbJ/7x5CKUEdnMQD/wOGS0+V7eV8cWi2dmkXI/vSjQUTkbz/Zm9iXXZPcKBp5Dos0Cu/J93LX9
w52btuxpRFVYWxs+Ric2Q4rH8wGP/z1SAyL1/wUy9IxAvR4BAA==
'

# ------------------------------------------------------------------ 输出样式 --
if [[ -t 1 ]]; then
  R=$'\e[1;31m'; G=$'\e[1;32m'; Y=$'\e[1;33m'; C=$'\e[1;36m'
  B=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
else
  R=; G=; Y=; C=; B=; D=; N=
fi

info() { printf '  %s %s\n' "${D}·${N}" "$*"; }
ok()   { printf '  %s %s\n' "${G}✔${N}" "$*"; }
warn() { printf '  %s %s\n' "${Y}⚠${N}" "$*"; }
die()  { printf '  %s %s\n' "${R}✘${N}" "$*" >&2; exit 1; }
step() { printf '\n%s\n' "${C}${B}▶ $*${N}"; }

usage() {
  cat <<EOF
${APP} 安装器 v${VERSION}

用法：
  bash install.sh [选项]

选项：
  --prefix DIR     安装前缀，默认 ${DEFAULT_PREFIX}
                   （二进制落在 DIR/sbin，DIR/bin 下建软链）
  --with-deps      顺便用 apt 安装 iptables 与 iptables-persistent
  --force          跳过发行版检查（非 Debian 系也能装）
  --uninstall      卸载程序（保留 /etc/iptables-wizard 备份目录）
  --purge          与 --uninstall 一起用，连备份与配置一起删除
  --check          只校验内嵌脚本完整性与版本，不安装
  --version        显示版本
  -h, --help       显示本帮助

示例：
  curl -fsSL https://example.com/install.sh | sudo bash
  sudo bash install.sh --prefix /usr --with-deps
  sudo bash install.sh --uninstall --purge
EOF
}

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

need_root() {
  if [[ ${EUID} -ne 0 ]]; then
    die "需要 root 权限：请用 sudo 运行（例如 curl -fsSL ... | sudo bash）"
  fi
}

# ---------------------------------------------------------------- 负载处理 ---
TMP_BIN=""
cleanup() { [[ -n ${TMP_BIN} && -f ${TMP_BIN} ]] && rm -f "${TMP_BIN}" 2>/dev/null || true; }
trap cleanup EXIT

decode_payload() {   # decode_payload 输出文件路径
  local out="$1"
  cmd_exists base64 || die "缺少 base64 命令（apt-get install -y coreutils）"
  cmd_exists gzip   || die "缺少 gzip 命令（apt-get install -y gzip）"
  if ! printf '%s' "${PAYLOAD_B64}" | base64 -d 2>/dev/null | gzip -dc >"${out}" 2>/dev/null; then
    die "内嵌负载解压失败，安装包可能已损坏"
  fi
  [[ -s ${out} ]] || die "内嵌负载为空，安装包可能已损坏"
}

verify_payload() {   # verify_payload 文件路径
  local f="$1" actual
  cmd_exists sha256sum || { warn "缺少 sha256sum，跳过完整性校验"; return 0; }
  actual=$(sha256sum "${f}" | awk '{print $1}')
  if [[ ${actual} != "${PAYLOAD_SHA256}" ]]; then
    die "完整性校验失败：期望 ${PAYLOAD_SHA256:0:16}…，实际 ${actual:0:16}…"
  fi
  ok "完整性校验通过（sha256 ${actual:0:16}…）"
}

prepare_payload() {
  TMP_BIN="$(mktemp /tmp/${APP}.XXXXXX)" || die "无法创建临时文件"
  decode_payload "${TMP_BIN}"
  verify_payload "${TMP_BIN}"
  if ! bash -n "${TMP_BIN}" 2>/dev/null; then
    die "内嵌脚本语法检查失败，安装包可能已损坏"
  fi
  ok "语法检查通过"
}

# ---------------------------------------------------------------- 环境检查 ---
os_id() {
  [[ -r /etc/os-release ]] || { printf 'unknown'; return 0; }
  sed -n 's/^ID=["]\{0,1\}\([^"]*\)["]\{0,1\}$/\1/p' /etc/os-release | head -n 1
}

check_os() {
  local id
  id=$(os_id)
  case "${id}" in
    debian|ubuntu|linuxmint|kali|raspbian|pop|elementary|zorin|deepin|armbian)
      ok "系统检查：${id}" ;;
    *)
      if [[ ${FORCE} == 1 ]]; then
        warn "未识别的发行版（${id:-unknown}），已按 --force 继续"
      else
        warn "本脚本面向 Debian / Ubuntu 系（当前：${id:-unknown}）"
        warn "如确认可用，请加 --force 重新执行"
        exit 1
      fi ;;
  esac
}

# ------------------------------------------------------------------ 安装 -----
do_install() {
  local prefix="$1"

  need_root
  check_os
  prepare_payload

  step "安装程序到 ${prefix}"
  mkdir -p "${prefix}/sbin" "${prefix}/bin"
  install -m 0755 -o root -g root "${TMP_BIN}" "${prefix}/sbin/${APP}" \
    || die "写入 ${prefix}/sbin 失败"
  ok "已安装 ${prefix}/sbin/${APP}"
  ln -sfn "${prefix}/sbin/${APP}" "${prefix}/bin/${APP}"
  ok "已创建软链 ${prefix}/bin/${APP}"

  step "准备数据目录"
  mkdir -p /etc/iptables-wizard/backups
  chmod 700 /etc/iptables-wizard /etc/iptables-wizard/backups 2>/dev/null || true
  ok "备份目录 /etc/iptables-wizard/backups"

  if [[ ${WITH_DEPS} == 1 ]]; then
    step "安装依赖（iptables / iptables-persistent）"
    if cmd_exists apt-get; then
      DEBIAN_FRONTEND=noninteractive apt-get update -qq || warn "apt-get update 失败，继续尝试安装"
      DEBIAN_FRONTEND=noninteractive apt-get install -y iptables iptables-persistent netfilter-persistent \
        || warn "依赖安装失败，请手动执行：apt-get install -y iptables iptables-persistent"
      ok "依赖处理完成"
    else
      warn "未找到 apt-get，跳过依赖安装"
    fi
  fi

  step "安装完成"
  printf '  %s\n' "${B}常用命令：${N}"
  printf '    %s   %s\n' "${C}sudo ${APP}${N}"         "进入交互式管理界面（推荐）"
  printf '    %s   %s\n' "${C}sudo ${APP} doctor${N}"  "环境自检"
  printf '    %s   %s\n' "${C}sudo ${APP} status${N}"  "查看防火墙状态"
  printf '\n'
  if ! cmd_exists iptables; then
    warn "当前系统还没有 iptables，可执行：apt-get install -y iptables iptables-persistent"
  fi
  info "备份目录：/etc/iptables-wizard/backups"
  info "卸载：sudo bash install.sh --uninstall"
  printf '\n'
}

do_uninstall() {
  local prefix="$1" target
  need_root
  step "卸载 ${APP}"
  target="${prefix}/sbin/${APP}"
  if [[ -f ${target} ]]; then
    rm -f "${target}"
    ok "已删除 ${target}"
  else
    warn "未找到 ${target}，可能安装在其他前缀（用 --prefix 指定）"
  fi
  [[ -L ${prefix}/bin/${APP} ]] && { rm -f "${prefix}/bin/${APP}"; ok "已删除软链 ${prefix}/bin/${APP}"; }

  if [[ ${PURGE} == 1 ]]; then
    if [[ -d /etc/iptables-wizard ]]; then
      rm -rf /etc/iptables-wizard
      ok "已删除配置与备份 /etc/iptables-wizard"
    fi
    info "系统防火墙规则（/etc/iptables/rules.v4）未删除，如需清理请手动处理"
  else
    info "已保留备份目录 /etc/iptables-wizard（如需一并删除加 --purge）"
  fi
  printf '\n'
}

do_check() {
  step "校验内嵌脚本"
  prepare_payload
  local v
  v=$(bash "${TMP_BIN}" --version 2>/dev/null || printf '未知')
  ok "内嵌脚本版本：${v}"
  info "安装器版本：${VERSION}"
  printf '\n'
}

# ------------------------------------------------------------------ 主流程 ---
PREFIX="${DEFAULT_PREFIX}"
ACTION="install"
FORCE=0
WITH_DEPS=0
PURGE=0

parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      --prefix)
        [[ -n ${2:-} ]] || die "--prefix 需要一个目录参数"
        PREFIX="${2%/}"
        shift 2 ;;
      --prefix=*) PREFIX="${1#*=}"; PREFIX="${PREFIX%/}"; shift ;;
      --with-deps) WITH_DEPS=1; shift ;;
      --force)     FORCE=1; shift ;;
      --uninstall) ACTION="uninstall"; shift ;;
      --purge)     PURGE=1; shift ;;
      --check)     ACTION="check"; shift ;;
      --version)   printf '%s %s\n' "${APP}-installer" "${VERSION}"; exit 0 ;;
      -h|--help)   usage; exit 0 ;;
      *)           die "未知参数：$1（用 --help 查看用法）" ;;
    esac
  done
  [[ -n ${PREFIX} ]] || die "--prefix 不能为空"
}

main() {
  parse_args "$@"
  printf '\n%s\n' "${C}${B}╭────────────────────────────────────────────────────╮${N}"
  printf '%s\n'   "${C}${B}│${N}  ${B}${APP}${N} ${D}安装器 v${VERSION}${N}"
  printf '%s\n'   "${C}${B}╰────────────────────────────────────────────────────╯${N}"

  case "${ACTION}" in
    install)   do_install "${PREFIX}" ;;
    uninstall) do_uninstall "${PREFIX}" ;;
    check)     do_check ;;
    *)         die "未知操作：${ACTION}" ;;
  esac
}

main "$@"
