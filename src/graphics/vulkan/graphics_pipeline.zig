const root  = @import("index.zig");
const std   = @import("std");
const c     = @import("cimports");

pub const ShaderSource = struct {
   bytecode          : [] align(@sizeOf(u32)) const u8,
   entrypoint        : [*:0] const u8,
};

pub const ClearColorTag = enum {
   none,
   color,
};

pub const ClearColor = union(ClearColorTag) {
   none  : void,
   color : root.types.Color.Rgba(f32),
};

pub const GraphicsPipeline = struct {
   vk_render_pass                            : c.VkRenderPass,
   vk_descriptor_set_layout_uniform_buffers  : c.VkDescriptorSetLayout,
   vk_pipeline_layout                        : c.VkPipelineLayout,
   vk_pipeline                               : c.VkPipeline,

   pub const CreateInfo = struct {
      vk_device               : c.VkDevice,
      swapchain_configuration : * const root.SwapchainConfiguration,
      shader_vertex           : ShaderSource,
      shader_fragment         : ShaderSource,
      clear_mode              : ClearColorTag,
   };

   pub const CreateError = error {
      OutOfMemory,
      InvalidShader,
   };

   pub fn create(create_info : * const CreateInfo) CreateError!@This() {
      var vk_result : c.VkResult = undefined;

      const vk_device               = create_info.vk_device;
      const swapchain_configuration = create_info.swapchain_configuration;
      const shader_vertex           = &create_info.shader_vertex;
      const shader_fragment         = &create_info.shader_fragment;
      const clear_mode              = create_info.clear_mode;

      const vk_shader_module_vertex = try _createShaderModule(vk_device, shader_vertex.bytecode);
      defer c.vkDestroyShaderModule(vk_device, vk_shader_module_vertex, null);

      const vk_shader_module_fragment = try _createShaderModule(vk_device, shader_fragment.bytecode);
      defer c.vkDestroyShaderModule(vk_device, vk_shader_module_fragment, null);

      const vk_render_pass = try _createRenderPass(vk_device, swapchain_configuration, clear_mode);
      errdefer c.vkDestroyRenderPass(vk_device, vk_render_pass, null);

      const vk_descriptor_set_layout_uniform_buffers = try _createDescriptorSetLayoutUniformBuffers(vk_device);
      errdefer c.vkDestroyDescriptorSetLayout(vk_device, vk_descriptor_set_layout_uniform_buffers, null);

      const vk_pipeline_layout = try _createPipelineLayout(vk_device, vk_descriptor_set_layout_uniform_buffers);
      errdefer c.vkDestroyPipelineLayout(vk_device, vk_pipeline_layout, null);

      const vk_info_create_shader_stage_vertex = c.VkPipelineShaderStageCreateInfo{
         .sType               = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
         .pNext               = null,
         .flags               = 0x00000000,
         .stage               = c.VK_SHADER_STAGE_VERTEX_BIT,
         .module              = vk_shader_module_vertex,
         .pName               = shader_vertex.entrypoint,
         .pSpecializationInfo = null,
      };

      const vk_info_create_shader_stage_fragment = c.VkPipelineShaderStageCreateInfo{
         .sType               = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
         .pNext               = null,
         .flags               = 0x00000000,
         .stage               = c.VK_SHADER_STAGE_FRAGMENT_BIT,
         .module              = vk_shader_module_fragment,
         .pName               = shader_fragment.entrypoint,
         .pSpecializationInfo = null,
      };

      const vk_infos_create_shader_stages = [_] c.VkPipelineShaderStageCreateInfo {
         vk_info_create_shader_stage_vertex,
         vk_info_create_shader_stage_fragment,
      };

      const vk_dynamic_states = [_] c.VkDynamicState {
         c.VK_DYNAMIC_STATE_VIEWPORT,
         c.VK_DYNAMIC_STATE_SCISSOR,
      };

      const vk_vertex_binding_description = c.VkVertexInputBindingDescription{
         .binding    = 0,
         .stride     = @sizeOf(root.types.Vertex),
         .inputRate  = c.VK_VERTEX_INPUT_RATE_VERTEX,
      };

      const vk_vertex_attribute_descriptions = [root.types.Vertex.INFO.Count] c.VkVertexInputAttributeDescription {
         .{
            .location   = root.types.Vertex.INFO.Index.Color,
            .binding    = 0,
            .format     = c.VK_FORMAT_R32G32B32A32_SFLOAT,
            .offset     = @offsetOf(root.types.Vertex, "color"),
         },
         .{
            .location   = root.types.Vertex.INFO.Index.Sample,
            .binding    = 0,
            .format     = c.VK_FORMAT_R32G32_SFLOAT,
            .offset     = @offsetOf(root.types.Vertex, "sample"),
         },
         .{
            .location   = root.types.Vertex.INFO.Index.Position,
            .binding    = 0,
            .format     = c.VK_FORMAT_R32G32B32_SFLOAT,
            .offset     = @offsetOf(root.types.Vertex, "position"),
         },
      };

      const vk_info_create_vertex_input_state = c.VkPipelineVertexInputStateCreateInfo{
         .sType                           = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
         .pNext                           = null,
         .flags                           = 0x00000000,
         .vertexBindingDescriptionCount   = 1,
         .pVertexBindingDescriptions      = &vk_vertex_binding_description,
         .vertexAttributeDescriptionCount = @intCast(vk_vertex_attribute_descriptions.len),
         .pVertexAttributeDescriptions    = &vk_vertex_attribute_descriptions,
      };

      const vk_info_create_dynamic_state = c.VkPipelineDynamicStateCreateInfo{
         .sType               = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
         .pNext               = null,
         .flags               = 0x00000000,
         .dynamicStateCount   = @intCast(vk_dynamic_states.len),
         .pDynamicStates      = &vk_dynamic_states,
      };

      const vk_info_create_input_assembly_state = c.VkPipelineInputAssemblyStateCreateInfo{
         .sType                  = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
         .pNext                  = null,
         .flags                  = 0x00000000,
         .topology               = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP,
         .primitiveRestartEnable = c.VK_TRUE,
      };

      const vk_info_create_viewport_state = c.VkPipelineViewportStateCreateInfo{
         .sType         = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
         .pNext         = null,
         .flags         = 0x00000000,
         .viewportCount = 1,
         .pViewports    = null,
         .scissorCount  = 1,
         .pScissors     = null,
      };

      const vk_info_create_rasterization_state = c.VkPipelineRasterizationStateCreateInfo{
         .sType                     = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
         .pNext                     = null,
         .flags                     = 0x00000000,
         .depthClampEnable          = c.VK_FALSE,
         .rasterizerDiscardEnable   = c.VK_FALSE,
         .polygonMode               = c.VK_POLYGON_MODE_FILL,
         .cullMode                  = c.VK_CULL_MODE_BACK_BIT,
         .frontFace                 = c.VK_FRONT_FACE_CLOCKWISE,
         .depthBiasEnable           = c.VK_FALSE,
         .depthBiasConstantFactor   = 0.0,
         .depthBiasClamp            = 0.0,
         .depthBiasSlopeFactor      = 0.0,
         .lineWidth                 = 1.0,
      };

      const vk_info_create_multisample_state = c.VkPipelineMultisampleStateCreateInfo{
         .sType                  = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
         .pNext                  = null,
         .flags                  = 0x00000000,
         .rasterizationSamples   = c.VK_SAMPLE_COUNT_1_BIT,
         .sampleShadingEnable    = c.VK_FALSE,
         .minSampleShading       = 1.0,
         .pSampleMask            = null,
         .alphaToCoverageEnable  = c.VK_FALSE,
         .alphaToOneEnable       = c.VK_FALSE,
      };

      const vk_info_create_color_blend_attachment_state = c.VkPipelineColorBlendAttachmentState{
         .blendEnable         = c.VK_FALSE,
         .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
         .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
         .colorBlendOp        = c.VK_BLEND_OP_ADD,
         .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
         .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
         .alphaBlendOp        = c.VK_BLEND_OP_ADD,
         .colorWriteMask      = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
      };

      const vk_info_create_color_blend_state = c.VkPipelineColorBlendStateCreateInfo{
         .sType            = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
         .pNext            = null,
         .flags            = 0x00000000,
         .logicOpEnable    = c.VK_FALSE,
         .logicOp          = c.VK_LOGIC_OP_COPY,
         .attachmentCount  = 1,
         .pAttachments     = &vk_info_create_color_blend_attachment_state,
         .blendConstants   = [4] f32 {0.0, 0.0, 0.0, 0.0},
      };

      const vk_info_create_graphics_pipeline = c.VkGraphicsPipelineCreateInfo{
         .sType               = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
         .pNext               = null,
         .flags               = 0x00000000,
         .stageCount          = @intCast(vk_infos_create_shader_stages.len),
         .pStages             = &vk_infos_create_shader_stages,
         .pVertexInputState   = &vk_info_create_vertex_input_state,
         .pInputAssemblyState = &vk_info_create_input_assembly_state,
         .pTessellationState  = null,
         .pViewportState      = &vk_info_create_viewport_state,
         .pRasterizationState = &vk_info_create_rasterization_state,
         .pMultisampleState   = &vk_info_create_multisample_state,
         .pDepthStencilState  = null,
         .pColorBlendState    = &vk_info_create_color_blend_state,
         .pDynamicState       = &vk_info_create_dynamic_state,
         .layout              = vk_pipeline_layout,
         .renderPass          = vk_render_pass,
         .subpass             = 0,
         .basePipelineHandle  = @ptrCast(@alignCast(c.VK_NULL_HANDLE)),
         .basePipelineIndex   = -1,
      };

      var vk_pipeline : c.VkPipeline = undefined;
      vk_result = c.vkCreateGraphicsPipelines(vk_device, @ptrCast(@alignCast(c.VK_NULL_HANDLE)), 1, &vk_info_create_graphics_pipeline, null, &vk_pipeline);
      switch (vk_result) {
         c.VK_SUCCESS                        => {},
         c.VK_PIPELINE_COMPILE_REQUIRED_EXT  => {},
         c.VK_ERROR_OUT_OF_HOST_MEMORY       => return error.OutOfMemory,
         c.VK_ERROR_OUT_OF_DEVICE_MEMORY     => return error.OutOfMemory,
         c.VK_ERROR_INVALID_SHADER_NV        => return error.InvalidShader,
         else                                => unreachable,
      }
      errdefer c.vkDestroyPipeline(vk_device, vk_pipeline, null);

      return @This(){
         .vk_render_pass                           = vk_render_pass,
         .vk_descriptor_set_layout_uniform_buffers = vk_descriptor_set_layout_uniform_buffers,
         .vk_pipeline_layout                       = vk_pipeline_layout,
         .vk_pipeline                              = vk_pipeline,
      };
   }

   pub fn destroy(self : @This(), vk_device : c.VkDevice) void {
      c.vkDestroyPipeline(vk_device, self.vk_pipeline, null);
      c.vkDestroyPipelineLayout(vk_device, self.vk_pipeline_layout, null);
      c.vkDestroyDescriptorSetLayout(vk_device, self.vk_descriptor_set_layout_uniform_buffers, null);
      c.vkDestroyRenderPass(vk_device, self.vk_render_pass, null);
      return;
   }
};

fn _createShaderModule(vk_device : c.VkDevice, bytecode : [] align(@sizeOf(u32)) const u8) GraphicsPipeline.CreateError!c.VkShaderModule {
   var vk_result : c.VkResult = undefined;

   const vk_info_create_shader_module = c.VkShaderModuleCreateInfo{
      .sType      = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
      .pNext      = null,
      .flags      = 0x00000000,
      .codeSize   = @intCast(bytecode.len),
      .pCode      = @ptrCast(bytecode.ptr),
   };

   var vk_shader_module : c.VkShaderModule = undefined;
   vk_result = c.vkCreateShaderModule(vk_device, &vk_info_create_shader_module, null, &vk_shader_module);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      c.VK_ERROR_INVALID_SHADER_NV     => return error.InvalidShader,
      else                             => unreachable,
   }
   errdefer c.vkDestroyShaderModule(vk_device, vk_shader_module, null);

   return vk_shader_module;
}

fn _createPipelineLayout(vk_device : c.VkDevice, vk_descriptor_set_layout : c.VkDescriptorSetLayout) GraphicsPipeline.CreateError!c.VkPipelineLayout {
   var vk_result : c.VkResult = undefined;

   const vk_push_constants_range = c.VkPushConstantRange{
      .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
      .offset     = 0,
      .size       = @sizeOf(root.types.PushConstants),
   };

   const vk_info_create_pipeline_layout = c.VkPipelineLayoutCreateInfo{
      .sType                  = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
      .pNext                  = null,
      .flags                  = 0x00000000,
      .setLayoutCount         = 1,
      .pSetLayouts            = &vk_descriptor_set_layout,
      .pushConstantRangeCount = 1,
      .pPushConstantRanges    = &vk_push_constants_range,
   };

   var vk_pipeline_layout : c.VkPipelineLayout = undefined;
   vk_result = c.vkCreatePipelineLayout(vk_device, &vk_info_create_pipeline_layout, null, &vk_pipeline_layout);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      else                             => unreachable,
   }
   errdefer c.vkDestroyPipelineLayout(vk_device, vk_pipeline_layout, null);

   return vk_pipeline_layout;
}

fn _createRenderPass(vk_device : c.VkDevice, swapchain_configuration : * const root.SwapchainConfiguration, clear_mode : ClearColorTag) GraphicsPipeline.CreateError!c.VkRenderPass {
   var vk_result : c.VkResult = undefined;

   const vk_color_load_op : c.VkAttachmentLoadOp = blk: {
      switch (clear_mode) {
         .none    => break :blk c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
         .color   => break :blk c.VK_ATTACHMENT_LOAD_OP_CLEAR,
      }
   };

   const vk_attachment_descriptor = c.VkAttachmentDescription{
      .flags            = 0x00000000,
      .format           = swapchain_configuration.format.format,
      .samples          = c.VK_SAMPLE_COUNT_1_BIT,
      .loadOp           = vk_color_load_op,
      .storeOp          = c.VK_ATTACHMENT_STORE_OP_STORE,
      .stencilLoadOp    = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
      .stencilStoreOp   = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
      .initialLayout    = c.VK_IMAGE_LAYOUT_UNDEFINED,
      .finalLayout      = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
   };

   const vk_attachment_reference = c.VkAttachmentReference{
      .attachment = 0,
      .layout     = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
   };

   const vk_subpass_description = c.VkSubpassDescription{
      .flags                     = 0x00000000,
      .pipelineBindPoint         = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
      .inputAttachmentCount      = 0,
      .pInputAttachments         = undefined,
      .colorAttachmentCount      = 1,
      .pColorAttachments         = &vk_attachment_reference,
      .pResolveAttachments       = null,
      .pDepthStencilAttachment   = null,
      .preserveAttachmentCount   = 0,
      .pPreserveAttachments      = undefined,
   };

   const vk_info_create_subpass_dependency = c.VkSubpassDependency{
      .srcSubpass       = c.VK_SUBPASS_EXTERNAL,
      .dstSubpass       = 0,
      .srcStageMask     = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      .dstStageMask     = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      .srcAccessMask    = 0x00000000,
      .dstAccessMask    = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
      .dependencyFlags  = 0x00000000,
   };

   const vk_info_create_render_pass = c.VkRenderPassCreateInfo{
      .sType            = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
      .pNext            = null,
      .flags            = 0x00000000,
      .attachmentCount  = 1,
      .pAttachments     = &vk_attachment_descriptor,
      .subpassCount     = 1,
      .pSubpasses       = &vk_subpass_description,
      .dependencyCount  = 1,
      .pDependencies    = &vk_info_create_subpass_dependency,
   };

   var vk_render_pass : c.VkRenderPass = undefined;
   vk_result = c.vkCreateRenderPass(vk_device, &vk_info_create_render_pass, null, &vk_render_pass);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      else                             => unreachable,
   }
   errdefer c.vkDestroyRenderPass(vk_device, vk_render_pass, null);

   return vk_render_pass;
}

fn _createDescriptorSetLayoutUniformBuffers(vk_device : c.VkDevice) GraphicsPipeline.CreateError!c.VkDescriptorSetLayout {
   var vk_result : c.VkResult = undefined;

   const vk_info_descriptor_set_layout_binding_uniforms = c.VkDescriptorSetLayoutBinding{
      .binding             = 0,
      .descriptorType      = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
      .descriptorCount     = 1,
      .stageFlags          = c.VK_SHADER_STAGE_VERTEX_BIT,
      .pImmutableSamplers  = null,
   };

   const vk_infos_descriptor_set_layout_bindings = [_] c.VkDescriptorSetLayoutBinding{
      vk_info_descriptor_set_layout_binding_uniforms,
   };

   const vk_info_create_descriptor_set_layout = c.VkDescriptorSetLayoutCreateInfo{
      .sType         = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
      .pNext         = null,
      .flags         = 0x00000000,
      .bindingCount  = @intCast(vk_infos_descriptor_set_layout_bindings.len),
      .pBindings     = &vk_infos_descriptor_set_layout_bindings,
   };

   var vk_descriptor_set_layout : c.VkDescriptorSetLayout = undefined;
   vk_result = c.vkCreateDescriptorSetLayout(vk_device, &vk_info_create_descriptor_set_layout, null, &vk_descriptor_set_layout);
   switch (vk_result) {
      c.VK_SUCCESS                     => {},
      c.VK_ERROR_OUT_OF_HOST_MEMORY    => return error.OutOfMemory,
      c.VK_ERROR_OUT_OF_DEVICE_MEMORY  => return error.OutOfMemory,
      else                             => unreachable,
   }
   errdefer c.vkDestroyDescriptorSetLayout(vk_device, vk_descriptor_set_layout, null);

   return vk_descriptor_set_layout;
}

