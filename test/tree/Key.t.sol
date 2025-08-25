// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import { Key, KeyImpl } from "../../src/tree/Key.sol";

contract KeyTest is Test {
    function testMakeExplode() public {
        Key k = KeyImpl.make(48, 16);
        (uint24 base, uint24 width) = k.explode();
        assertEq(base, 48);
        assertEq(width, 16);

        assertEq(k.base(), 48);
        assertEq(k.width(), 16);

        assertFalse(k.isEmpty());
        assertFalse(k.isEq(KeyImpl.make(16, 48)));
        assertFalse(k.isEq(KeyImpl.make(48, 4)));
    }

    function testIsEmpty() public {
        Key k = Key.wrap(0);
        assertTrue(k.isEmpty());
    }

    function testIsEq() public {
        Key k1 = KeyImpl.make(1, 2);
        Key k2 = KeyImpl.make(1, 2);
        assertTrue(k1.isEq(k2));
    }

    function testIsAbove() public {
        Key k1 = KeyImpl.make(384, 128);
        Key k2 = KeyImpl.make(384, 64);
        assertTrue(k1.isAbove(k2));
        k2 = KeyImpl.make(384 + 64, 64);
        assertTrue(k1.isAbove(k2));
        k2 = KeyImpl.make(384 - 64, 64);
        assertTrue(k1.isAbove(k2));
        // Same height
        k2 = KeyImpl.make(256, 128);
        assertFalse(k1.isAbove(k2));
        // Below but in sibling subtree
        k2 = KeyImpl.make(256, 64);
        assertTrue(k1.isAbove(k2));
        // Above
        k2 = KeyImpl.make(256, 256);
        assertFalse(k1.isAbove(k2));
    }

    function testIsBelow() public {
        Key k1 = KeyImpl.make(36, 4);
        Key k2 = KeyImpl.make(32, 32);
        assertTrue(k1.isBelow(k2));
        k2 = KeyImpl.make(64, 16);
        assertTrue(k1.isBelow(k2));
        k2 = KeyImpl.make(64, 4);
        assertFalse(k1.isBelow(k2));
        k2 = KeyImpl.make(16, 1);
        assertFalse(k1.isBelow(k2));
    }

    function testIsLeaf() public {
        Key k1 = KeyImpl.make(2, 1);
        Key k2 = KeyImpl.make(2, 2);
        assertTrue(k1.isLeaf());
        assertFalse(k2.isLeaf());
    }

    function testIsLeft() public {
        Key k1 = KeyImpl.make(1, 1);
        Key k2 = KeyImpl.make(2, 1);
        assertTrue(k1.isLeft(k2));
        assertFalse(k2.isLeft(k1));
    }

    function testIsRight() public {
        Key k1 = KeyImpl.make(2, 1);
        Key k2 = KeyImpl.make(1, 1);
        assertTrue(k1.isRight(k2));
        assertFalse(k2.isRight(k1));
    }

    function testNextDown() public {
        Key k = KeyImpl.make(1, 1);
        Key next = k.nextDown();
        assertEq(next.base(), 0);
        assertEq(next.width(), 1);
    }

    function testParent() public {
        Key k = KeyImpl.make(1, 1);
        Key parent = k.parent();
        assertEq(parent.base(), 0);
        assertEq(parent.width(), 1);
    }

    function testChildren() public {
        Key k = KeyImpl.make(1, 1);
        Key[] memory children = k.children();
        assertEq(children.length, 2);
        assertEq(children[0].base(), 0);
        assertEq(children[0].width(), 1);
        assertEq(children[1].base(), 1);
        assertEq(children[1].width(), 1);
    }

    function testSibling() public {
        Key k1 = KeyImpl.make(1, 1);
        Key k2 = KeyImpl.make(1, 2);
        assertEq(k1.sibling(), k2);
        assertEq(k2.sibling(), k1);
    }

    function testLow() public {
        Key k = KeyImpl.make(1, 1);
        Key low = k.low();
        assertEq(low.base(), 0);
        assertEq(low.width(), 1);
    }

    function testHigh() public {
        Key k = KeyImpl.make(1, 1);
        Key high = k.high();
        assertEq(high.base(), 1);
        assertEq(high.width(), 1);
    }

    function testTicks() public {}
}
