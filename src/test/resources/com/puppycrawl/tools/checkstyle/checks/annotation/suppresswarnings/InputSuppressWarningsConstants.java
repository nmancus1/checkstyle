package com.puppycrawl.tools.checkstyle.checks.annotation.suppresswarnings;

import java.util.List;
import java.util.ArrayList;

public class InputSuppressWarningsConstants
{
    public static final String UNCHECKED = "unchecked";

    public static void test() {
        @SuppressWarnings(UNCHECKED) // ok
        final List<String> dummyOne = (List<String>) new ArrayList();
        @SuppressWarnings(InputSuppressWarningsConstants.UNCHECKED) // ok
        final List<String> dummyTwo = (List<String>) new ArrayList();
    }
}
