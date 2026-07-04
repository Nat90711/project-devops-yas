package com.yas.recommendation.kafka.consumer;

import static org.mockito.Mockito.mock;

import com.yas.commonlibrary.kafka.cdc.message.ProductCdcMessage;
import com.yas.commonlibrary.kafka.cdc.message.ProductMsgKey;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.MockitoAnnotations;

class ProductSyncDataConsumerTest {

    @InjectMocks
    private ProductSyncDataConsumer productSyncDataConsumer;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
    }

    @Test
    void testProcessDltMessage_shouldExecuteWithoutException() {
        // Given
        ProductMsgKey key = ProductMsgKey.builder().id(1L).build();
        ProductCdcMessage message = ProductCdcMessage.builder()
                .op(com.yas.commonlibrary.kafka.cdc.message.Operation.CREATE)
                .build();
        
        // When & Then
        org.junit.jupiter.api.Assertions.assertDoesNotThrow(() -> 
            productSyncDataConsumer.processDltMessage(key, message, null)
        );
    }
}
